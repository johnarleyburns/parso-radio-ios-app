import Foundation

/// Fetches etree (Live Music Archive) shows for a specific month-day,
/// caches the full result set for 24 hours, and picks a random entry
/// from the cache on each refresh.
struct LiveMusicOnThisDayService {
    private let session: URLSession
    private let cacheKey: String
    private let poolKey: String
    private let poolDateKey: String
    private let state = State()

    private final class State { var lastPickedID: String? }

    init(session: URLSession = .app) {
        self.session = session
        let today = Self.todayKey()
        self.cacheKey = "liveMusicEntry_" + today
        self.poolKey = "liveMusicPool_" + today
        self.poolDateKey = "liveMusicPoolDate_" + today
    }

    // MARK: - Public

    func fetchDailyEntry(forceFresh: Bool = false) async -> LiveMusicEntry? {
        let pool = await getOrRefreshPool()
        guard let pool, !pool.isEmpty else { return nil }

        var candidates = pool
        if forceFresh, let lastID = state.lastPickedID, candidates.count > 1 {
            let fresh = candidates.filter { $0.id != lastID }
            if !fresh.isEmpty { candidates = fresh }
        }

        let pick = candidates.randomElement()!
        state.lastPickedID = pick.id

        if let enriched = try? await enrichWithMetadata(pick) {
            cacheSingle(enriched)
            return enriched
        }
        cacheSingle(pick)
        return pick
    }

    func clearCachedEntry() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: poolKey)
        UserDefaults.standard.removeObject(forKey: poolDateKey)
        state.lastPickedID = nil
    }

    // MARK: - Pool cache (24-hour TTL)

    private func isPoolExpired() -> Bool {
        let poolDate = UserDefaults.standard.double(forKey: poolDateKey)
        guard poolDate > 0 else { return true }
        let cached = Date(timeIntervalSince1970: poolDate)
        // Expire at midnight local time
        return !Calendar.current.isDate(cached, inSameDayAs: Date())
    }

    private func getOrRefreshPool() async -> [LiveMusicEntry]? {
        if !isPoolExpired(), let pool = cachedPool() { return pool }

        guard let entries = try? await fetchEntries(for: Self.todayMMDD()),
              !entries.isEmpty else { return cachedPool() }

        cachePool(entries)
        return entries
    }

    private func cachedPool() -> [LiveMusicEntry]? {
        guard let data = UserDefaults.standard.data(forKey: poolKey),
              let entries = try? JSONDecoder().decode([LiveMusicEntry].self, from: data)
        else { return nil }
        return entries
    }

    private func cachePool(_ entries: [LiveMusicEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: poolKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: poolDateKey)
    }

    private func cacheSingle(_ entry: LiveMusicEntry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    func fetchEntries(for mmdd: String) async throws -> [LiveMusicEntry] {
        let query = #"collection:(etree) AND "\#(mmdd)""#
        return try await searchEtree(query: query, mmdd: mmdd)
    }

    // MARK: - Metadata enrichment

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
                title: nil, venue: doc.extractVenue(), coverage: nil,
                date: doc.date, year: doc.year,
                downloads: doc.downloads ?? 0,
                dateString: mmdd,                 description: doc.description
            )
        }
    }

    // MARK: - Helpers

    static func todayMMDD() -> String {
        let df = DateFormatter(); df.dateFormat = "MM-dd"
        return df.string(from: Date())
    }

    static func todayKey() -> String { todayMMDD() }
}

// MARK: - IA Response models

private struct EtreeSearchResponse: Decodable {
    let response: EtreeResponseBody
}
private struct EtreeResponseBody: Decodable { let docs: [EtreeDoc] }
private struct EtreeDoc: Decodable {
    let identifier: String; let creator: String?; let date: String?; let year: Int?; let downloads: Int?; let description: String?
    enum CodingKeys: String, CodingKey { case identifier, creator, date, year, downloads, description }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        creator = try? c.decode(String.self, forKey: .creator)
        date = try? c.decode(String.self, forKey: .date)
        description = try? c.decode(String.self, forKey: .description)
        if let y = try? c.decode(Int.self, forKey: .year) { year = y }
        else if let s = try? c.decode(String.self, forKey: .year) { year = Int(s) }
        else { year = nil }
        if let d = try? c.decode(Int.self, forKey: .downloads) { downloads = d }
        else if let s = try? c.decode(String.self, forKey: .downloads) { downloads = Int(s) }
        else { downloads = nil }
    }
    func extractVenue() -> String? {
        guard let desc = description else { return nil }
        let parts = desc.components(separatedBy: " • ")
        guard parts.count >= 3 else { return nil }
        return parts[2].trimmingCharacters(in: .whitespaces)
    }
}
