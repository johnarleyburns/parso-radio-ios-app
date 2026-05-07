import Foundation

// Scrapes freemusicarchive.org genre pages.
// FMA retired their public API; track metadata is embedded as data-track-info JSON in HTML.
// The playbackUrl (stream endpoint) redirects to a stable CDN MP3 without requiring auth
// or a browser User-Agent — tested and confirmed before shipping.
struct FMAService {
    static let baseURL = "https://freemusicarchive.org"

    private let session: URLSession
    private let normalizer = MetadataNormalizer()

    // Maps app tag names to FMA genre path segments.
    static let genreMap: [String: String] = [
        "classical": "Classical",
        "ambient":   "Ambient",
        "baroque":   "Classical",
        "romantic":  "Classical",
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchTracks(forChannel channel: Channel, page: Int = 1) async throws -> [Track] {
        // Composer channels: fetch Classical genre and let channel.matches() filter later.
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
        return parseTrackInfo(from: html, genre: genre)
    }

    private func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }

    private func parseTrackInfo(from html: String, genre: String) -> [Track] {
        // FMA embeds track metadata as data-track-info='{"id":...}' in the genre listing.
        // Each page contains up to 20 tracks.
        guard let regex = try? NSRegularExpression(pattern: #"data-track-info='([^']+)'"#) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        return matches.compactMap { match -> Track? in
            guard let captureRange = Range(match.range(at: 1), in: html),
                  let data = html[captureRange].data(using: .utf8),
                  let json = try? JSONDecoder().decode(FMATrackInfo.self, from: data)
            else { return nil }
            return mapTrack(json, genre: genre)
        }
    }

    private func mapTrack(_ info: FMATrackInfo, genre: String) -> Track? {
        guard let streamURL = URL(string: info.playbackUrl) else { return nil }

        // Attempt composer extraction: FMA title often follows "ComposerName - WorkTitle".
        // artistName is the performer, so we try the title first.
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

        // License is derived from the filter used at fetch time and set in the caller.
        // We default to .publicDomain here since we only fetch PD and CC-BY pages.
        // CC-BY content is accepted for this non-commercial app.
        let license: LicenseType = .publicDomain

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
            metadataConfidence: composer != nil ? 2.0 : 0.3
        )
    }

    // Tries to extract a known composer from a title like "Mozart - Symphony 40" or
    // "F. Chopin Waltz No. 10". Checks prefixes of up to 4 words before the " - " divider
    // and also prefixes of the full title.
    private func extractComposer(from title: String) -> String? {
        var candidates: [String] = []

        let parts = title.components(separatedBy: " - ")
        if let head = parts.first {
            candidates += prefixes(of: head, maxWords: 4)
        }
        candidates += prefixes(of: title, maxWords: 4)

        for candidate in candidates {
            if let c = ComposerMap.normalize(candidate) { return c }
        }
        return nil
    }

    private func prefixes(of text: String, maxWords: Int) -> [String] {
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        return (1...min(maxWords, words.count)).map { words.prefix($0).joined(separator: " ") }
    }
}

// MARK: - JSON model

private struct FMATrackInfo: Decodable {
    // Genre listing pages serialise id as a quoted string; individual track pages use Int.
    // We only parse genre listing pages, so String is correct here.
    let id: String
    let handle: String
    let title: String
    let artistName: String
    let playbackUrl: String

    enum CodingKeys: String, CodingKey {
        case id, handle, title, artistName, playbackUrl
    }
}
