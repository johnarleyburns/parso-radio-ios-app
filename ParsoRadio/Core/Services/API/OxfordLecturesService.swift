import Foundation

// Fetches audio lectures from Oxford University's podcast system (podcasts.ox.ac.uk).
// Three-level crawl: unit page → series pages (parallel) → audio.xml RSS feeds (parallel).
// Series that only have a video.xml feed (1 GB MP4s) are silently skipped.
struct OxfordLecturesService {
    private let session: URLSession

    init(session: URLSession = .app) {
        self.session = session
    }

    func fetchTracks(unitSlug: String) async throws -> [Track] {
        let seriesSlugs = try await fetchSeriesSlugs(unitSlug: unitSlug)
        var allTracks: [Track] = []
        await withTaskGroup(of: [Track].self) { group in
            for slug in seriesSlugs {
                group.addTask {
                    (try? await self.fetchTracksForSeries(slug, unitSlug: unitSlug)) ?? []
                }
            }
            for await tracks in group {
                allTracks.append(contentsOf: tracks)
            }
        }
        var seen = Set<String>()
        return allTracks.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Private

    // Fetches a URL and rejects responses larger than 10 MB before string conversion.
    private func safeFetch(_ url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        guard data.count < 10_000_000 else { throw URLError(.badServerResponse) }
        return data
    }

    private func fetchSeriesSlugs(unitSlug: String) async throws -> [String] {
        let url = URL(string: "https://podcasts.ox.ac.uk/units/\(unitSlug)")!
        let data = try await safeFetch(url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        guard let regex = try? NSRegularExpression(pattern: #"href="/series/([^"]+)""#) else { return [] }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var slugs: [String] = []
        var seen = Set<String>()
        for m in matches {
            guard let r = Range(m.range(at: 1), in: html) else { continue }
            let slug = String(html[r])
            if seen.insert(slug).inserted { slugs.append(slug) }
        }
        if slugs.isEmpty {
            print("OxfordLecturesService: no series slugs found for unit '\(unitSlug)'")
        }
        return slugs
    }

    private func fetchTracksForSeries(_ seriesSlug: String, unitSlug: String) async throws -> [Track] {
        let url = URL(string: "https://podcasts.ox.ac.uk/series/\(seriesSlug)")!
        let data = try await safeFetch(url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        // Skip series that only have a video feed — we want audio.xml only.
        guard let regex = try? NSRegularExpression(pattern: #"/feeds/([a-f0-9-]{36})/audio\.xml"#),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else {
            print("OxfordLecturesService: no audio.xml feed for series '\(seriesSlug)' (video-only or changed HTML)")
            return []
        }
        let seriesTitle = extractSeriesTitle(from: html) ?? seriesSlug
        return try await fetchRSSFeed(uuid: String(html[r]), unitSlug: unitSlug,
                                       seriesSlug: seriesSlug, seriesTitle: seriesTitle)
    }

    private func extractSeriesTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<h1[^>]*>([\s\S]*?)</h1>"#),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchRSSFeed(uuid: String, unitSlug: String,
                              seriesSlug: String, seriesTitle: String) async throws -> [Track] {
        let url = URL(string: "https://podcasts.ox.ac.uk/feeds/\(uuid)/audio.xml")!
        let data = try await safeFetch(url)
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        return parseItems(xml: xml, unitSlug: unitSlug, seriesSlug: seriesSlug, seriesTitle: seriesTitle)
    }

    private func parseItems(xml: String, unitSlug: String,
                            seriesSlug: String, seriesTitle: String) -> [Track] {
        guard let regex = try? NSRegularExpression(
            pattern: "<item>(.*?)</item>",
            options: .dotMatchesLineSeparators
        ) else { return [] }
        let items = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { m -> Track? in
            guard let r = Range(m.range(at: 1), in: xml) else { return nil }
            return parseItem(String(xml[r]), unitSlug: unitSlug)
        }
        let total = items.count
        return items.enumerated().map { index, track in
            guard total > 1 else { return track }
            var t = track
            t.partNumber = index + 1
            t.totalParts = total
            t.parentIdentifier = seriesSlug
            t.collectionTitle = seriesTitle
            return t
        }
    }

    private func parseItem(_ item: String, unitSlug: String) -> Track? {
        guard let title = extractTag("title", from: item), !title.isEmpty else { return nil }
        guard let audioURL = extractEnclosureURL(from: item) else { return nil }
        let duration = parseDuration(extractTag("itunes:duration", from: item))
        let guid = extractTag("guid", from: item) ?? ""
        let trackId = oxfordTrackId(from: guid)
        let artist = extractTag("itunes:author", from: item)
            ?? extractTag("author", from: item)
            ?? "University of Oxford"
        return Track(
            id: trackId,
            source: "oxford_lectures",
            title: decodeEntities(title),
            artist: decodeEntities(artist),
            duration: duration,
            streamURL: audioURL,
            downloadURL: nil,
            localFilePath: nil,
            license: .ccBy,
            tags: ["oxford-lectures", unitSlug],
            qualityScore: 1.0,
            rawCreator: "University of Oxford",
            composer: nil,
            instruments: [],
            metadataConfidence: 2.0
        )
    }

    // Extracts text content between <tag> and </tag>, handling optional attributes
    // on the opening tag and stripping CDATA wrappers.
    private func extractTag(_ tag: String, from text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        guard let regex = try? NSRegularExpression(
            pattern: "<\(escaped)(?:\\s[^>]*)?>([\\s\\S]*?)</\(escaped)>",
            options: .dotMatchesLineSeparators
        ),
        let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let r = Range(m.range(at: 1), in: text) else { return nil }
        let raw = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("<![CDATA[") && raw.hasSuffix("]]>") {
            let inner = String(raw.dropFirst(9).dropLast(3))
            return inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.isEmpty ? nil : raw
    }

    // Returns the URL from the first <enclosure> tag that has type="audio/mpeg".
    private func extractEnclosureURL(from item: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: "<enclosure[^>]+>") else { return nil }
        let matches = regex.matches(in: item, range: NSRange(item.startIndex..., in: item))
        for m in matches {
            guard let r = Range(m.range, in: item) else { continue }
            let tag = String(item[r])
            guard tag.contains("audio/mpeg") else { continue }
            guard let urlRegex = try? NSRegularExpression(pattern: #"url="([^"]+)""#),
                  let um = urlRegex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let ur = Range(um.range(at: 1), in: tag) else { continue }
            return URL(string: String(tag[ur]))
        }
        return nil
    }

    // Parses itunes:duration which Oxford uses as plain seconds (e.g. "924")
    // but also handles HH:MM:SS or MM:SS formats.
    private func parseDuration(_ raw: String?) -> Double {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return 0 }
        if let seconds = Double(s) { return seconds }
        let parts = s.split(separator: ":").compactMap { Double($0) }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return 0
    }

    // Derives a stable ID from the Oxford GUID: "http://...tag:...:file:{NUMBER}:audio"
    private func oxfordTrackId(from guid: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #":file:(\d+):"#),
              let m = regex.firstMatch(in: guid, range: NSRange(guid.startIndex..., in: guid)),
              let r = Range(m.range(at: 1), in: guid) else {
            return "oxford-\(abs(guid.hashValue))"
        }
        return "oxford-\(guid[r])"
    }

    private func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
