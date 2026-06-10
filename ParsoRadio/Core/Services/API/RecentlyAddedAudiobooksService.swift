import Foundation

/// Fetches the most popular recently-added LibriVox audiobooks from the
/// Internet Archive, caches the full result set for 24 hours, and picks
/// a random entry from the cache on each refresh (without re-querying IA).
struct RecentlyAddedAudiobooksService {
    private let session: URLSession
    private let cacheKey = "dailyAudiobook"
    private let poolKey = "audiobookPool"
    private let poolDateKey = "audiobookPoolDate"
    private let state = State()

    private final class State {
        var lastPickedID: String?
    }

    init(session: URLSession = .app) {
        self.session = session
    }

    // MARK: - Public

    func fetchDailyEntry(forceFresh: Bool = false) async -> AudiobookEntry? {
        // If pool is stale (>24h) or doesn't exist, refresh from IA
        let pool = await getOrRefreshPool()

        guard let pool, !pool.isEmpty else { return nil }

        // Pick a random entry, avoiding the last-picked ID if possible
        var candidates = pool
        if forceFresh, let lastID = state.lastPickedID, candidates.count > 1 {
            let fresh = candidates.filter { $0.id != lastID }
            if !fresh.isEmpty { candidates = fresh }
        }

        let pick = candidates.randomElement()!
        state.lastPickedID = pick.id

        // Enrich with full metadata
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
        return !Calendar.current.isDate(cached, inSameDayAs: Date())
    }

    private func getOrRefreshPool() async -> [AudiobookEntry]? {
        if !isPoolExpired(), let pool = cachedPool() {
            return pool
        }

        guard let entries = try? await fetchRecentAudiobooks(),
              !entries.isEmpty else {
            // Return stale pool if IA is unavailable
            return cachedPool()
        }

        cachePool(entries)
        return entries
    }

    private func cachedPool() -> [AudiobookEntry]? {
        guard let data = UserDefaults.standard.data(forKey: poolKey),
              let entries = try? JSONDecoder().decode([AudiobookEntry].self, from: data)
        else { return nil }
        return entries
    }

    private func cachePool(_ entries: [AudiobookEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: poolKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: poolDateKey)
    }

    private func cacheSingle(_ entry: AudiobookEntry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    // MARK: - Metadata enrichment

    private func enrichWithMetadata(_ entry: AudiobookEntry) async throws -> AudiobookEntry {
        guard let encoded = entry.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let metaURL = URL(string: "https://archive.org/metadata/\(encoded)")
        else { return entry }

        let (data, _) = try await session.data(from: metaURL)
        struct IAMetaEnvelope: Decodable {
            struct Meta: Decodable {
                let title: String?
                let creator: String?
                let description: String?
                let date: String?
            }
            let metadata: Meta
        }
        let envelope = try JSONDecoder().decode(IAMetaEnvelope.self, from: data)
        let meta = envelope.metadata

        return AudiobookEntry(
            id: entry.id,
            title: meta.title ?? entry.title,
            creator: meta.creator ?? entry.creator,
            date: meta.date ?? entry.date,
            downloads: entry.downloads,
            description: meta.description ?? entry.description
        )
    }

    // MARK: - IA Query

    private func fetchRecentAudiobooks() async throws -> [AudiobookEntry] {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let agoString = ISO8601DateFormatter().string(from: sixtyDaysAgo).prefix(10)

        let query = "collection:librivoxaudio AND addeddate:[\(agoString) TO \(today)] AND language:(eng OR english)"

        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [
            URLQueryItem(name: "q",       value: query),
            URLQueryItem(name: "fl[]",    value: "identifier"),
            URLQueryItem(name: "fl[]",    value: "title"),
            URLQueryItem(name: "fl[]",    value: "creator"),
            URLQueryItem(name: "fl[]",    value: "date"),
            URLQueryItem(name: "fl[]",    value: "downloads"),
            URLQueryItem(name: "fl[]",    value: "description"),
            URLQueryItem(name: "output",  value: "json"),
            URLQueryItem(name: "rows",    value: "20"),
            URLQueryItem(name: "sort[]",  value: "downloads desc"),
        ]
        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(IAResponse.self, from: data)
        return response.response.docs.map { doc in
            AudiobookEntry(
                id: doc.identifier,
                title: doc.title,
                creator: doc.creator,
                date: doc.date,
                downloads: doc.downloads ?? 0,
                description: doc.description
            )
        }
    }
}

// MARK: - IA Response models

private struct IAResponse: Decodable {
    struct Body: Decodable { let docs: [Doc] }
    struct Doc: Decodable {
        let identifier: String
        let title: String?
        let creator: String?
        let date: String?
        let downloads: Int?
        let description: String?

        enum CodingKeys: String, CodingKey { case identifier, title, creator, date, downloads, description }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            identifier  = try c.decode(String.self, forKey: .identifier)
            title       = try? c.decode(String.self, forKey: .title)
            date        = try? c.decode(String.self, forKey: .date)
            description = try? c.decode(String.self, forKey: .description)
            if let arr = try? c.decode([String].self, forKey: .creator) {
                creator = arr.first
            } else {
                creator = try? c.decode(String.self, forKey: .creator)
            }
            if let d = try? c.decode(Int.self, forKey: .downloads) {
                downloads = d
            } else if let s = try? c.decode(String.self, forKey: .downloads), let d = Int(s) {
                downloads = d
            } else {
                downloads = nil
            }
        }
    }
    let response: Body
}
