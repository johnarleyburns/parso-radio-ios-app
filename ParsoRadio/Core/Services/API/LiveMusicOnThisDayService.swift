import Foundation

/// Fetches etree (Live Music Archive) shows that occurred on a specific
/// month-day across any year, picks one at random, enriches it with full
/// IA metadata, and caches the daily pick so it stays consistent all day.
struct LiveMusicOnThisDayService {
    private let session: URLSession
    private let cacheKey: String

    init(session: URLSession = .app) {
        self.session = session
        self.cacheKey = "liveMusicEntry_" + Self.todayKey()
    }

    // MARK: - Public

    /// Returns a random live show from IA etree for today's MM-DD,
    /// enriched with full metadata. Uses a cached pick if available.
    func fetchDailyEntry() async -> LiveMusicEntry? {
        if let cached = cachedEntry(), cached.dateString == Self.todayKey() {
            return cached
        }
        clearCachedEntry()

        guard let entries = try? await fetchEntries(for: Self.todayMMDD()),
              !entries.isEmpty else { return nil }

        let pick = entries.randomElement()!

        // Enrich with full metadata from IA /metadata endpoint
        if let enriched = try? await enrichWithMetadata(pick) {
            cacheEntry(enriched)
            return enriched
        }

        cacheEntry(pick)
        return pick
    }

    /// For testing: fetch entries for an arbitrary MM-DD without caching.
    func fetchEntries(for mmdd: String) async throws -> [LiveMusicEntry] {
        let query = #"collection:(etree) AND "\#(mmdd)""#
        return try await searchEtree(query: query, mmdd: mmdd)
    }

    func clearCachedEntry() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    // MARK: - Cache

    private func cachedEntry() -> LiveMusicEntry? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let entry = try? JSONDecoder().decode(LiveMusicEntry.self, from: data)
        else { return nil }
        return entry
    }

    private func cacheEntry(_ entry: LiveMusicEntry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    // MARK: - Metadata enrichment

    /// Fetches full IA metadata for an entry to get venue, coverage, title, etc.
    private func enrichWithMetadata(_ entry: LiveMusicEntry) async throws -> LiveMusicEntry {
        guard let encoded = entry.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let metaURL = URL(string: "https://archive.org/metadata/\(encoded)")
        else { return entry }

        let (data, _) = try await session.data(from: metaURL)
        struct IAMetaEnvelope: Decodable {
            struct Meta: Decodable {
                let title: String?
                let creator: String?
                let venue: String?
                let coverage: String?
                let date: String?
                let year: String?
                let description: String?
            }
            let metadata: Meta
        }
        let envelope = try JSONDecoder().decode(IAMetaEnvelope.self, from: data)
        let meta = envelope.metadata

        return LiveMusicEntry(
            id: entry.id,
            creator: meta.creator ?? entry.creator,
            title: meta.title,
            venue: meta.venue ?? entry.venue,
            coverage: meta.coverage,
            date: meta.date ?? entry.date,
            year: entry.year,
            downloads: entry.downloads,
            dateString: entry.dateString,
            description: meta.description ?? entry.description
        )
    }

    // MARK: - IA Query

    private func searchEtree(query: String, mmdd: String) async throws -> [LiveMusicEntry] {
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [
            URLQueryItem(name: "q",       value: query),
            URLQueryItem(name: "fl[]",    value: "identifier"),
            URLQueryItem(name: "fl[]",    value: "creator"),
            URLQueryItem(name: "fl[]",    value: "date"),
            URLQueryItem(name: "fl[]",    value: "year"),
            URLQueryItem(name: "fl[]",    value: "downloads"),
            URLQueryItem(name: "fl[]",    value: "description"),
            URLQueryItem(name: "output",  value: "json"),
            URLQueryItem(name: "rows",    value: "50"),
            URLQueryItem(name: "sort[]",  value: "downloads desc"),
        ]
        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(EtreeSearchResponse.self, from: data)
        return response.response.docs.compactMap { doc in
            LiveMusicEntry(
                id: doc.identifier,
                creator: doc.creator ?? "Unknown Artist",
                title: nil,
                venue: doc.extractVenue(),
                coverage: nil,
                date: doc.date,
                year: doc.year,
                downloads: doc.downloads ?? 0,
                dateString: mmdd,
                description: nil
            )
        }
    }

    // MARK: - Helpers

    static func todayMMDD() -> String {
        let df = DateFormatter()
        df.dateFormat = "MM-dd"
        return df.string(from: Date())
    }

    static func todayKey() -> String {
        todayMMDD()
    }
}

// MARK: - IA Response models for etree search

private struct EtreeSearchResponse: Decodable {
    let response: EtreeResponseBody
}

private struct EtreeResponseBody: Decodable {
    let docs: [EtreeDoc]
}

private struct EtreeDoc: Decodable {
    let identifier: String
    let creator: String?
    let date: String?
    let year: Int?
    let downloads: Int?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case identifier, creator, date, year, downloads, description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier  = try c.decode(String.self, forKey: .identifier)
        creator     = try? c.decode(String.self, forKey: .creator)
        date        = try? c.decode(String.self, forKey: .date)
        downloads   = try? c.decode(Int.self, forKey: .downloads)
        description = try? c.decode(String.self, forKey: .description)
        if let y = try? c.decode(Int.self, forKey: .year) {
            year = y
        } else if let s = try? c.decode(String.self, forKey: .year), let y = Int(s) {
            year = y
        } else {
            year = nil
        }
    }

    func extractVenue() -> String? {
        guard let desc = description else { return nil }
        let parts = desc.components(separatedBy: " • ")
        guard parts.count >= 3 else { return nil }
        return parts[2].trimmingCharacters(in: .whitespaces)
    }
}
