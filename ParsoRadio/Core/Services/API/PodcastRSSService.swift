import Foundation

/// Fetches and parses podcast RSS feeds for News channels.
/// Returns Track objects from <enclosure> tags; uses itunes:duration when available.
final class PodcastRSSService {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchTracks(channel: Channel) async throws -> [Track] {
        guard let feedURL = channel.feedURL,
              let url = URL(string: feedURL),
              url.scheme == "https" else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, _) = try await session.data(for: request)
        guard data.count < 10_000_000 else { throw URLError(.badServerResponse) }
        // RSS feeds are newest-first; items come out in feed order.
        let items = RSSXMLParser().parse(data: data)
        return items.compactMap { $0.toTrack(channelId: channel.id) }
    }
}

// MARK: - XML parser

private final class RSSXMLParser: NSObject, XMLParserDelegate {
    private var items: [RSSItem] = []
    private var current: RSSItem?
    private var text = ""

    func parse(data: Data) -> [RSSItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attrs: [String: String] = [:]) {
        text = ""
        if name == "item" { current = RSSItem() }
        if name == "enclosure", let item = current {
            item.enclosureURL  = attrs["url"] ?? ""
            item.enclosureType = attrs["type"] ?? ""
            if let len = attrs["length"], let l = Int(len) { item.enclosureLength = l }
        }
        if name == "itunes:image", let item = current {
            item.itunesImageHref = attrs["href"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard let item = current else { text = ""; return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title":
            if item.title.isEmpty { item.title = trimmed }
        case "itunes:duration":
            item.itunesDuration = trimmed
        case "pubDate":
            item.pubDate = trimmed
        case "item":
            items.append(item)
            current = nil
        default: break
        }
        text = ""
    }
}

// MARK: - Data model

private final class RSSItem {
    var title = ""
    var enclosureURL = ""
    var enclosureType = ""
    var enclosureLength = 0
    var itunesDuration = ""
    var pubDate = ""
    var itunesImageHref: String? = nil

    func toTrack(channelId: String) -> Track? {
        guard !enclosureURL.isEmpty,
              enclosureType.hasPrefix("audio"),
              let url = URL(string: enclosureURL) else { return nil }

        let dur = parsedDuration ?? Double(enclosureLength) / 16000.0  // ~128 kbps fallback

        // Stable ID using deterministic FNV-1a hash of the URL — not Swift's .hash which
        // is randomised per process and would break 30-day play-history tracking.
        let urlHash = enclosureURL.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        let stableId = channelId + "-" + String(urlHash, radix: 16)

        // pubDate encoded as Unix timestamp → DB sorts by quality_score DESC = newest first.
        let pubTimestamp = Self.parseRSSDate(pubDate) ?? 0
        let pubDate: Date? = pubTimestamp > 0 ? Date(timeIntervalSince1970: pubTimestamp) : nil

        return Track(
            id: stableId,
            source: "podcast",
            title: title.isEmpty ? "Episode" : title,
            artist: displayName(for: channelId),
            duration: max(dur, 30),
            streamURL: url,
            downloadURL: nil,
            localFilePath: nil,
            license: .publicDomain,
            tags: [channelId],
            qualityScore: pubTimestamp,
            rawCreator: "",
            composer: nil,
            instruments: [],
            metadataConfidence: 2.0,
            addedDate: pubDate,
            artworkURLString: itunesImageHref
        )
    }

    // Parses RFC 2822 pub dates; handles both "GMT" and "+0000" timezone forms.
    static func parseRSSDate(_ string: String) -> Double? {
        guard !string.isEmpty else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, dd MMM yyyy HH:mm:ss Z",
                    "EEE, dd MMM yyyy HH:mm:ss zzz",
                    "dd MMM yyyy HH:mm:ss Z",
                    "dd MMM yyyy HH:mm:ss zzz"] {
            df.dateFormat = fmt
            if let d = df.date(from: string) { return d.timeIntervalSince1970 }
        }
        return nil
    }

    private var parsedDuration: Double? {
        guard !itunesDuration.isEmpty else { return nil }
        let parts = itunesDuration.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 1: return Double(parts[0])
        case 2: return Double(parts[0] * 60 + parts[1])
        case 3: return Double(parts[0] * 3600 + parts[1] * 60 + parts[2])
        default: return nil
        }
    }
}

private func displayName(for channelId: String) -> String {
    Channel.defaults.first { $0.id == channelId }?.name ?? channelId
}
