import Foundation

@MainActor
final class RecommendationsController {
    private let db: DatabaseService
    private let archiveService: InternetArchiveService

    init(db: DatabaseService, archiveService: InternetArchiveService) {
        self.db = db
        self.archiveService = archiveService
    }

    private static func allChannels() -> [Channel] {
        Channel.defaults + IACollectionStore.shared.channels
    }

    private static func categoryById() -> [String: String] {
        Dictionary(allChannels().map { ($0.id, $0.category) },
                   uniquingKeysWith: { a, _ in a })
    }

    func fetchMixedRecommendations() async throws -> [Track]? {
        let history = await db.fetchRecentlyPlayedWithChannel(limit: 200)
        let catById = Self.categoryById()
        let musicHistory = history.filter { (catById[$0.channelId] ?? "") == "Curated Music" }
        let bookHistory = history.filter { (catById[$0.channelId] ?? "") == "Audiobooks" }

        let musicWeights = RecommendationQueryBuilder.channelWeights(
            fromHistory: musicHistory, categoryFilter: ["Curated Music"], categoryById: catById)
        let bookWeights = RecommendationQueryBuilder.channelWeights(
            fromHistory: bookHistory, categoryFilter: ["Audiobooks"], categoryById: catById)

        let musicAlloc = RecommendationQueryBuilder.allocateSamples(weights: musicWeights)
        let bookAlloc = RecommendationQueryBuilder.allocateSamples(weights: bookWeights)
        let totalAllocations = musicAlloc.count + bookAlloc.count
        guard totalAllocations > 0 else { return nil }

        let all = Self.allChannels()
        let svc = archiveService
        let stampTags = ["for-you"]
        var musicPool: [Track] = []
        var bookPool: [Track] = []

        await withTaskGroup(of: (isBook: Bool, tracks: [Track]).self) { group in
            for (channelId, count) in musicAlloc {
                guard let source = all.first(where: { $0.id == channelId }),
                      let entry = source.iaQueryEntry else { continue }
                group.addTask {
                    let tracks = (try? await Self.withTimeout(15) {
                        try await svc.fetchTracks(iaQuery: entry.iaQuery, matchTags: stampTags)
                    }) ?? []
                    return (false, Array(tracks.shuffled().prefix(count)))
                }
            }
            for (channelId, count) in bookAlloc {
                guard let source = all.first(where: { $0.id == channelId }),
                      let entry = source.iaQueryEntry else { continue }
                group.addTask {
                    let tracks = (try? await Self.withTimeout(15) {
                        try await svc.fetchTracks(iaQuery: entry.iaQuery, matchTags: stampTags)
                    }) ?? []
                    return (true, Array(tracks.shuffled().prefix(count)))
                }
            }
            for await result in group {
                if result.isBook { bookPool.append(contentsOf: result.tracks) }
                else { musicPool.append(contentsOf: result.tracks) }
            }
        }

        let playedIds = Set(history.map(\.track.id))
        var seen = Set<String>()
        var mixed: [Track] = []
        var mi = 0, bi = 0
        while mi < musicPool.count || bi < bookPool.count {
            if mi < musicPool.count {
                let t = musicPool[mi]; mi += 1
                if !playedIds.contains(t.id), seen.insert(t.id).inserted { mixed.append(t) }
            }
            if bi < bookPool.count {
                let t = bookPool[bi]; bi += 1
                if !playedIds.contains(t.id), seen.insert(t.id).inserted { mixed.append(t) }
            }
        }
        return mixed.isEmpty ? nil : mixed
    }

    func fetchRecommendations(for channel: Channel) async throws -> [Track]? {
        let history = await db.fetchRecentlyPlayedWithChannel(limit: 200)
        let catById = Self.categoryById()
        let isBooks = channel.id == "books-for-you"
        let relevantCats: Set<String> = isBooks ? ["Audiobooks"] : ["Curated Music"]
        let relevantPlays = history.filter { relevantCats.contains(catById[$0.channelId] ?? "") }
        guard relevantPlays.count >= RecommendationQueryBuilder.minPlays else { return nil }

        let weights = RecommendationQueryBuilder.channelWeights(
            fromHistory: history, categoryFilter: relevantCats, categoryById: catById)
        let allocations = RecommendationQueryBuilder.allocateSamples(weights: weights)
        guard !allocations.isEmpty else { return nil }

        let all = Self.allChannels()
        let svc = archiveService
        let stampTags = [channel.id]
        var pool: [Track] = []
        await withTaskGroup(of: [Track].self) { group in
            for (channelId, count) in allocations {
                guard let source = all.first(where: { $0.id == channelId }),
                      let entry = source.iaQueryEntry else { continue }
                group.addTask {
                    let tracks = (try? await Self.withTimeout(15) {
                        try await svc.fetchTracks(
                            iaQuery: entry.iaQuery, matchTags: stampTags)
                    }) ?? []
                    return Array(tracks.shuffled().prefix(count))
                }
            }
            for await tracks in group { pool.append(contentsOf: tracks) }
        }

        let playedIds = Set(history.map(\.track.id))
        var seen = Set<String>()
        return pool.filter { !playedIds.contains($0.id) && seen.insert($0.id).inserted }
    }

    func fetchFallbackTracks(for channel: Channel) async -> [Track] {
        let isBooks = channel.id == "books-for-you"
        let fallbackCat: String = isBooks ? "Audiobooks" : "Curated Music"
        let sources = Self.allChannels().filter { $0.category == fallbackCat && $0.iaQueryEntry != nil }
        guard !sources.isEmpty else { return [] }

        let svc = archiveService
        let history = await db.fetchRecentlyPlayedWithChannel(limit: 200)
        let playedIds = Set(history.map(\.track.id))
        var pool: [Track] = []
        let perSource = max(5, 60 / sources.count)
        await withTaskGroup(of: [Track].self) { group in
            for source in sources {
                guard let entry = source.iaQueryEntry else { continue }
                group.addTask {
                    let tracks = (try? await Self.withTimeout(10) {
                        try await svc.fetchTracks(
                            iaQuery: entry.iaQuery, matchTags: [channel.id])
                    }) ?? []
                    return Array(tracks.shuffled().prefix(perSource))
                }
            }
            for await tracks in group { pool.append(contentsOf: tracks) }
        }
        var seen = Set<String>()
        return pool.shuffled().filter { !playedIds.contains($0.id) && seen.insert($0.id).inserted }
    }

    private static func withTimeout<T>(_ seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
