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
              let url = URL(string: feedURL) else { return [] }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 30
        let (data, _) = try await session.data(for: request)
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

    func toTrack(channelId: String) -> Track? {
        guard !enclosureURL.isEmpty,
              enclosureType.hasPrefix("audio"),
              let url = URL(string: enclosureURL) else { return nil }

        let dur = parsedDuration ?? Double(enclosureLength) / 16000.0  // ~128 kbps fallback
        let stableId = channelId + "-" + enclosureURL.hash.description

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
            qualityScore: 0.9,
            rawCreator: "",
            composer: nil,
            instruments: [],
            metadataConfidence: 0.0
        )
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
