import Foundation

/// Fetches the most popular recently-added LibriVox audiobooks from the
/// Internet Archive, picks one at random, enriches it with full metadata,
/// and caches the daily pick.
struct RecentlyAddedAudiobooksService {
    private let session: URLSession
    private let cacheKey = "dailyAudiobook"

    init(session: URLSession = .app) {
        self.session = session
    }

    // MARK: - Public

    func fetchDailyEntry() async -> AudiobookEntry? {
        if let cached = cachedEntry() { return cached }
        clearCachedEntry()

        guard let entries = try? await fetchRecentAudiobooks(),
              !entries.isEmpty else { return nil }

        let pick = entries.randomElement()!
        if let enriched = try? await enrichWithMetadata(pick) {
            cacheEntry(enriched)
            return enriched
        }
        cacheEntry(pick)
        return pick
    }

    func clearCachedEntry() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    // MARK: - Cache

    private func cachedEntry() -> AudiobookEntry? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let entry = try? JSONDecoder().decode(AudiobookEntry.self, from: data)
        else { return nil }
        return entry
    }

    private func cacheEntry(_ entry: AudiobookEntry) {
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
            URLQueryItem(name: "output",  value: "json"),
            URLQueryItem(name: "rows",    value: "50"),
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
                description: nil
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
    }
    let response: Body
}
