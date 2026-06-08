import Foundation
import CryptoKit

@MainActor
final class MetadataEnrichmentService: ObservableObject {
    @Published var isEnriching = false
    @Published var progress: (completed: Int, total: Int) = (0, 0)
    @Published var currentTrackTitle: String = ""

    private let db: DatabaseService
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Lorewave/1.0 (info@parso.guru)"]
        return URLSession(configuration: config)
    }()

    init(db: DatabaseService) {
        self.db = db
    }

    func enrichApprovedTracks(for channelId: String) async {
        guard !isEnriching else { return }
        isEnriching = true
        defer { isEnriching = false }

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

        // Step 1: MusicBrainz recording search
        if let mbRecording = await searchMusicBrainzRecording(title: title, artist: creator) {
            metadata.mbRecordingID = mbRecording.id
            metadata.durationMs = mbRecording.durationMs
            metadata.mbReleaseID = mbRecording.releaseMBID

            // Step 2: Work → Composer
            if let workID = mbRecording.workMBID {
                metadata.mbWorkID = workID
                if let work = await fetchMusicBrainzWork(workID) {
                    metadata.composer = work.composer
                    metadata.composerMBID = work.composerMBID
                    metadata.workTitle = work.title
                    metadata.genreTags = work.genres
                }
            }

            // Step 3: Composer portrait via Wikidata
            if let composerMBID = metadata.composerMBID {
                metadata.composerPortraitURL = await fetchWikidataPortrait(mbArtistID: composerMBID)?.absoluteString
            }

            // Step 4: Album art via Cover Art Archive
            if let releaseMBID = metadata.mbReleaseID {
                metadata.albumArtURL = "https://coverartarchive.org/release/\(releaseMBID)/front-500"
            }

            metadata.enrichmentSource = "musicbrainz"
        } else if !creator.isEmpty {
            // Fallback: try direct Wikidata lookup for author/composer
            metadata.composerPortraitURL = await fetchWikidataPortraitByName(creator)?.absoluteString
            if metadata.composerPortraitURL != nil {
                metadata.composer = creator
                metadata.enrichmentSource = "wikidata"
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
