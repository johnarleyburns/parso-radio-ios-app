import Foundation

// Scrapes freemusicarchive.org genre pages.
// FMA retired their public API; track metadata is embedded as data-track-info JSON in HTML.
// The playbackUrl (stream endpoint) redirects to a stable CDN MP3 without requiring auth
// or a browser User-Agent — tested and confirmed before shipping.
struct FMAService {
    static let baseURL = "https://freemusicarchive.org"

    private let session: URLSession
    private let normalizer = MetadataNormalizer()

    // Maps app tag names to FMA genre path segments (curl-verified).
    static let genreMap: [String: String] = [
        "classical":    "Classical",
        "ambient":      "Ambient",
        "baroque":      "Classical",
        "romantic":     "Classical",
        "jazz":         "Jazz",
        "blues":        "Blues",
        "rock":         "Rock",
        "country":      "Country",
        "folk":         "Folk",
        "old-time__historic": "Old-Time__Historic",
        "electronic":   "Electronic",
        "hip-hop":      "Hip-Hop",
        "lo-fi-hip-hop": "Lo-fi-Hip-Hop",
        "world music":  "International",
        "pop":          "Pop",
        "experimental": "Experimental",
        "instrumental": "Instrumental",
        "flamenco":     "International",
        "spanish":      "International",
        "soul":         "Soul-RB",
        "r&b":          "Soul-RB",
        "bossa nova":   "Jazz",
    ]

    init(session: URLSession = .app) {
        self.session = session
    }

    func fetchTracks(forChannel channel: Channel, page: Int = 1) async throws -> [Track] {
        // Composer channels: fetch Classical genre; channel.matches() filters by composer later.
        // Tag channels: map the first recognised tag to an FMA genre.
        let genre: String
        if !channel.composers.isEmpty {
            genre = "Classical"
        } else {
            let firstKnown = channel.tags.first { Self.genreMap[$0] != nil }
            genre = firstKnown.flatMap { Self.genreMap[$0] } ?? "Classical"
        }

        let pdTracks   = try await fetchGenre(genre: genre, licenseFilter: "music-filter-public-domain", page: page)
        let ccbyTracks = (try? await fetchGenre(genre: genre, licenseFilter: "music-filter-CC-attribution", page: page)) ?? []

        var seen = Set<String>()
        return (pdTracks + ccbyTracks).filter { seen.insert($0.id).inserted }
    }

    // MARK: - Private

    private func fetchGenre(genre: String, licenseFilter: String, page: Int) async throws -> [Track] {
        guard let url = URL(string: "\(Self.baseURL)/genre/\(genre)?pageSize=20&page=\(page)&\(licenseFilter)=1") else {
            throw URLError(.badURL)
        }
        let html = try await fetchHTML(url: url)
        let license: LicenseType = licenseFilter.contains("public-domain") ? .publicDomain : .ccBy
        return parseTrackInfo(from: html, genre: genre, license: license)
    }

    private func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        // FMA returns 403 without a browser-like UA; use a minimal mobile Safari string.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await session.data(for: request)
        guard data.count < 10_000_000 else { throw URLError(.badServerResponse) }
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }

    private func parseTrackInfo(from html: String, genre: String, license: LicenseType) -> [Track] {
        // FMA embeds track metadata as data-track-info='{"id":...}' in the genre listing.
        // Each page contains up to 20 tracks.
        guard let regex = try? NSRegularExpression(pattern: #"data-track-info='([^']+)'"#) else {
            print("FMAService: regex compilation failed for genre \(genre)")
            return []
        }
        let nsRange = NSRange(html.startIndex..., in: html)
        let tracks = regex.matches(in: html, range: nsRange).compactMap { match -> Track? in
            guard let captureRange = Range(match.range(at: 1), in: html),
                  let data = html[captureRange].data(using: .utf8),
                  let info = try? JSONDecoder().decode(FMATrackInfo.self, from: data)
            else { return nil }
            return mapTrack(info, genre: genre, license: license)
        }
        if tracks.isEmpty {
            print("FMAService: no tracks parsed for genre \(genre) (HTML length: \(html.count))")
        }
        return tracks
    }

    private func mapTrack(_ info: FMATrackInfo, genre: String, license: LicenseType) -> Track? {
        guard let streamURL = URL(string: info.playbackUrl),
              streamURL.scheme == "https" || streamURL.scheme == "http" else { return nil }

        // FMA title often follows "ComposerName - WorkTitle"; artistName is the performer.
        let composer = extractComposer(from: info.title)
            ?? ComposerMap.normalize(info.artistName)

        let (_, instruments, _) = normalizer.normalize(
            creator: composer,
            title: info.title,
            subjects: [genre.lowercased()],
            description: nil,
            licenseURL: nil,
            year: nil,
            duration: nil
        )

        return Track(
            id: "fma-\(info.id)",
            source: "fma",
            title: info.title,
            artist: info.artistName,
            duration: 0,
            streamURL: streamURL,
            downloadURL: nil,
            localFilePath: nil,
            license: license,
            tags: [genre.lowercased()],
            qualityScore: 0.6,
            rawCreator: info.artistName,
            composer: composer,
            instruments: instruments,
            metadataConfidence: 2.0,  // FMA is a curated, licensed source; not filtered by metadata quality
            artworkURLString: nil
        )
    }

    // Tries to extract a known composer from titles like "Mozart - Symphony 40",
    // "Bach: Brandenburg Concerto", or "Four Seasons (Spring) - Vivaldi".
    // Checks multiple separators and inspects both head and tail of each split.
    private func extractComposer(from title: String) -> String? {
        var candidates: [String] = []
        for sep in [" - ", ": ", " | ", " — "] {
            let parts = title.components(separatedBy: sep)
            if parts.count > 1 {
                candidates += prefixes(of: parts[0], maxWords: 4)
                candidates += prefixes(of: parts[parts.count - 1], maxWords: 4)
            }
        }
        candidates += prefixes(of: title, maxWords: 4)
        return candidates.lazy
            .compactMap { ComposerMap.normalize($0.trimmingCharacters(in: .whitespaces)) }
            .first
    }

    private func prefixes(of text: String, maxWords: Int) -> [String] {
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        return (1...min(maxWords, words.count)).map { words.prefix($0).joined(separator: " ") }
    }
}

// MARK: - JSON model

// id is serialised as a quoted string on genre listing pages (Int on individual track pages).
private struct FMATrackInfo: Decodable {
    let id: String
    let handle: String
    let title: String
    let artistName: String
    let playbackUrl: String

    enum CodingKeys: String, CodingKey {
        case id, handle, title, artistName, playbackUrl
    }
}
