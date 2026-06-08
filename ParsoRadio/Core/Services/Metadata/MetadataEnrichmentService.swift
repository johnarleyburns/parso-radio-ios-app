import Foundation
import CryptoKit

@MainActor
final class MetadataEnrichmentService: ObservableObject {
    @Published var isEnriching = false
    @Published var progress: (completed: Int, total: Int) = (0, 0)
    @Published var currentTrackTitle: String = ""

    private var db: DatabaseService?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Lorewave/1.0 (info@parso.guru)"]
        return URLSession(configuration: config)
    }()

    init() {}
    init(db: DatabaseService) { self.db = db }

    func enrichApprovedTracks(for channelId: String, db: DatabaseService) async {
        guard !isEnriching else { return }
        self.db = db
        isEnriching = true
        defer { isEnriching = false }

        guard let db = self.db else { return }
        let trackIDs = await db.fetchUnenrichedApprovedTrackIDs(channelId: channelId)
        guard !trackIDs.isEmpty else {
            progress = (0, 0)
            return
        }

        let approvedTracks = await db.fetchApprovedTracks(forChannelId: channelId)
        let tracksToEnrich = approvedTracks.filter { trackIDs.contains($0.id) }

        progress = (0, tracksToEnrich.count)

        for (index, track) in tracksToEnrich.enumerated() {
            guard isEnriching else { break }
            currentTrackTitle = track.title
            progress = (index + 1, tracksToEnrich.count)

            if let metadata = await enrichTrack(track) {
                await db.saveTrackMetadata(metadata)
            }

            // Respect MusicBrainz rate limit: ~1 req/sec
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }

    func stop() {
        isEnriching = false
        progress = (0, 0)
    }

    // MARK: - Single track enrichment

    private func enrichTrack(_ track: Track) async -> TrackMetadata? {
        let creator = clean(track.artist)
        let title = clean(track.title) ?? track.id

        var metadata = TrackMetadata(
            trackID: track.id,
            genreTags: [],
            enrichedAt: Date().timeIntervalSince1970,
            enrichmentSource: nil
        )

        // Check if this is likely an audiobook/spoken-word track
        // These have author names in the creator field; MusicBrainz won't help
        let isLikelyAudiobook = track.tags.contains(where: {
            $0.contains("librivox") || $0.contains("audiobook") || $0.contains("audio_book")
        }) || track.source == "internet_archive"

        // Step 1: Try MusicBrainz recording search (works for music)
        if !isLikelyAudiobook,
           let mbRecording = await searchMusicBrainzRecording(title: title, artist: creator) {
            metadata.mbRecordingID = mbRecording.id
            metadata.durationMs = mbRecording.durationMs
            metadata.mbReleaseID = mbRecording.releaseMBID

            if let workID = mbRecording.workMBID {
                metadata.mbWorkID = workID
                if let work = await fetchMusicBrainzWork(workID) {
                    metadata.composer = work.composer
                    metadata.composerMBID = work.composerMBID
                    metadata.workTitle = work.title
                    metadata.genreTags = work.genres
                }
            }

            if let composerMBID = metadata.composerMBID {
                metadata.composerPortraitURL = await fetchWikidataPortrait(mbArtistID: composerMBID)?.absoluteString
            }

            if let releaseMBID = metadata.mbReleaseID {
                metadata.albumArtURL = "https://coverartarchive.org/release/\(releaseMBID)/front-500"
            }

            metadata.enrichmentSource = "musicbrainz"
        } else if !creator.isEmpty {
            // For audiobooks/authors: direct Wikidata lookup
            if let authorData = await fetchWikidataAuthor(creator) {
                metadata.author = authorData.name
                metadata.authorPortraitURL = authorData.portraitURL?.absoluteString
                metadata.authorBirthDate = authorData.birthDate
                metadata.authorDeathDate = authorData.deathDate
                metadata.authorBio = authorData.bio
                metadata.composerPortraitURL = authorData.portraitURL?.absoluteString
                metadata.enrichmentSource = "wikidata"

                // Try Open Library for book cover (author + title search)
                if let coverURL = await fetchOpenLibraryCover(author: creator, title: title) {
                    metadata.albumArtURL = coverURL
                }
            } else {
                // Fallback: simple portrait lookup
                metadata.composerPortraitURL = await fetchWikidataPortraitByName(creator)?.absoluteString
                if metadata.composerPortraitURL != nil {
                    metadata.composer = creator
                    metadata.enrichmentSource = "wikidata"
                }
            }
        }

        // IA item thumbnail as track art
        if track.source == "internet_archive" {
            metadata.trackArtURL = "https://archive.org/services/img/\(track.id)"
        }

        return metadata
    }

    // MARK: - MusicBrainz API

    private struct MBRecordingResult {
        let id: String
        let durationMs: Int?
        let workMBID: String?
        let releaseMBID: String?
    }

    private func searchMusicBrainzRecording(title: String, artist: String) async -> MBRecordingResult? {
        guard let query = "recording:\(encode(title)) AND artistname:\(encode(artist))"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        guard let url = URL(string: "https://musicbrainz.org/ws/2/recording?query=\(query)&fmt=json&limit=1") else { return nil }

        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recordings = json["recordings"] as? [[String: Any]],
              let first = recordings.first else { return nil }

        let workMBID: String? = {
            guard let relations = first["relations"] as? [[String: Any]] else { return nil }
            for rel in relations where (rel["type"] as? String) == "performance" {
                return (rel["work"] as? [String: Any])?["id"] as? String
            }
            return nil
        }()

        let releaseMBID: String? = {
            guard let releases = first["releases"] as? [[String: Any]],
                  let r = releases.first else { return nil }
            return r["id"] as? String
        }()

        return MBRecordingResult(
            id: first["id"] as? String ?? "",
            durationMs: first["length"] as? Int,
            workMBID: workMBID,
            releaseMBID: releaseMBID
        )
    }

    private struct MBWorkResult {
        let title: String
        let composer: String?
        let composerMBID: String?
        let genres: [String]
    }

    private func fetchMusicBrainzWork(_ workID: String) async -> MBWorkResult? {
        guard let url = URL(string: "https://musicbrainz.org/ws/2/work/\(workID)?inc=artist-rels+tags+genres&fmt=json") else { return nil }

        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let composer: String?
        let composerMBID: String?
        if let relations = json["relations"] as? [[String: Any]] {
            let composerRel = relations.first { ($0["type"] as? String) == "composer" }
            composer = (composerRel?["artist"] as? [String: Any])?["name"] as? String
            composerMBID = (composerRel?["artist"] as? [String: Any])?["id"] as? String
        } else {
            composer = nil
            composerMBID = nil
        }

        let genres: [String] = {
            guard let tags = json["tags"] as? [[String: Any]] else { return [] }
            return tags.prefix(5).compactMap { $0["name"] as? String }
        }()

        return MBWorkResult(
            title: json["title"] as? String ?? "",
            composer: composer,
            composerMBID: composerMBID,
            genres: genres
        )
    }

    // MARK: - Wikidata

    private func fetchWikidataPortrait(mbArtistID: String) async -> URL? {
        guard let url = URL(string: "https://musicbrainz.org/ws/2/artist/\(mbArtistID)?inc=url-rels&fmt=json") else { return nil }
        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let relations = json["relations"] as? [[String: Any]] else { return nil }

        for rel in relations {
            if let type = rel["type"] as? String, type == "wikidata",
               let urlDict = rel["url"] as? [String: Any],
               let resource = urlDict["resource"] as? String {
                let qid = resource.components(separatedBy: "/").last ?? ""
                return await fetchCommonsImage(qid: qid)
            }
        }
        return nil
    }

    private func fetchWikidataPortraitByName(_ name: String) async -> URL? {
        guard let query = encode(name).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.wikidata.org/w/api.php?action=wbsearchentities&search=\(query)&language=en&format=json&limit=1") else { return nil }

        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let search = json["search"] as? [[String: Any]],
              let first = search.first,
              let qid = first["id"] as? String else { return nil }

        return await fetchCommonsImage(qid: qid)
    }

    private func fetchCommonsImage(qid: String) async -> URL? {
        guard let url = URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(qid).json") else { return nil }
        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = json["entities"] as? [String: Any],
              let entity = entities[qid] as? [String: Any],
              let claims = entity["claims"] as? [String: Any],
              let p18 = claims["P18"] as? [[String: Any]],
              let mainsnak = p18.first?["mainsnak"] as? [String: Any],
              let datavalue = mainsnak["datavalue"] as? [String: Any],
              let value = datavalue["value"] as? String else { return nil }

        let encoded = value.replacingOccurrences(of: " ", with: "_")
        let digest = Insecure.MD5.hash(data: Data(encoded.utf8))
        let md5 = digest.map { String(format: "%02x", $0) }.joined()
        return URL(string: "https://upload.wikimedia.org/wikipedia/commons/\(md5.prefix(1))/\(md5.prefix(2))/\(encoded)")
    }

    // MARK: - Wikidata Author Enrichment (for audiobooks)

    private struct AuthorData {
        let name: String
        let portraitURL: URL?
        let birthDate: String?
        let deathDate: String?
        let bio: String?
    }

    private func fetchWikidataAuthor(_ name: String) async -> AuthorData? {
        // Step 1: Search Wikidata for the author
        guard let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://www.wikidata.org/w/api.php?action=wbsearchentities&search=\(query)&language=en&format=json&limit=1") else { return nil }

        guard let (searchData, _) = try? await session.data(from: searchURL),
              let searchJson = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let search = searchJson["search"] as? [[String: Any]],
              let first = search.first,
              let qid = first["id"] as? String else { return nil }

        let label = first["label"] as? String ?? name
        let bio = first["description"] as? String

        // Step 2: Fetch entity data for dates and image
        guard let entityURL = URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(qid).json") else { return nil }

        let portraitURL: URL?
        let birthDate: String?
        let deathDate: String?

        if let (entityData, _) = try? await session.data(from: entityURL),
           let entityJson = try? JSONSerialization.jsonObject(with: entityData) as? [String: Any],
           let entities = entityJson["entities"] as? [String: Any],
           let entity = entities[qid] as? [String: Any],
           let claims = entity["claims"] as? [String: Any] {

            // Portrait (P18)
            if let p18 = claims["P18"] as? [[String: Any]],
               let mainsnak = p18.first?["mainsnak"] as? [String: Any],
               let datavalue = mainsnak["datavalue"] as? [String: Any],
               let filename = datavalue["value"] as? String {
                let encoded = filename.replacingOccurrences(of: " ", with: "_")
                let digest = Insecure.MD5.hash(data: Data(encoded.utf8))
                let md5 = digest.map { String(format: "%02x", $0) }.joined()
                portraitURL = URL(string: "https://upload.wikimedia.org/wikipedia/commons/\(md5.prefix(1))/\(md5.prefix(2))/\(encoded)")
            } else {
                portraitURL = nil
            }

            // Birth date (P569)
            if let p569 = claims["P569"] as? [[String: Any]],
               let mainsnak = p569.first?["mainsnak"] as? [String: Any],
               let datavalue = mainsnak["datavalue"] as? [String: Any],
               let timeStr = (datavalue["value"] as? [String: Any])?["time"] as? String {
                birthDate = formatWikidataDate(timeStr)
            } else {
                birthDate = nil
            }

            // Death date (P570)
            if let p570 = claims["P570"] as? [[String: Any]],
               let mainsnak = p570.first?["mainsnak"] as? [String: Any],
               let datavalue = mainsnak["datavalue"] as? [String: Any],
               let timeStr = (datavalue["value"] as? [String: Any])?["time"] as? String {
                deathDate = formatWikidataDate(timeStr)
            } else {
                deathDate = nil
            }
        } else {
            portraitURL = nil
            birthDate = nil
            deathDate = nil
        }

        return AuthorData(
            name: label,
            portraitURL: portraitURL,
            birthDate: birthDate,
            deathDate: deathDate,
            bio: bio
        )
    }

    private func formatWikidataDate(_ timeStr: String) -> String? {
        // Wikidata dates: +1860-05-29T00:00:00Z or -0428-00-00T00:00:00Z (BC)
        let cleaned = timeStr.replacingOccurrences(of: "+", with: "")
                              .replacingOccurrences(of: "T00:00:00Z", with: "")
        let parts = cleaned.components(separatedBy: "-")
        if parts[0].hasPrefix("-") { return "\(parts[0].dropFirst()) BC" }
        if parts.count >= 1 { return parts[0] }
        return cleaned
    }

    // MARK: - Open Library Cover Search (for audiobooks)

    private func fetchOpenLibraryCover(author: String, title: String) async -> String? {
        // Search by author + title
        let query = "author:\(encode(author)) title:\(encode(title))"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://openlibrary.org/search.json?\(encoded)&limit=3") else { return nil }

        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]] else { return nil }

        for doc in docs {
            // Prefer cover_i (numeric cover ID)
            if let coverID = doc["cover_i"] as? Int {
                return "https://covers.openlibrary.org/b/id/\(coverID)-M.jpg"
            }
            // Fallback to cover_edition_key
            if let editionKey = doc["cover_edition_key"] as? String {
                return "https://covers.openlibrary.org/b/olid/\(editionKey)-M.jpg"
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func encode(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func clean(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "unknown" else { return "" }
        return trimmed
    }
}
