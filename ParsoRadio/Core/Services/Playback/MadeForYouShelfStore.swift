import Foundation
import Combine

enum MadeForYouShelfState {
    case idle
    case loading
    case loaded(Kind, [Track])
    case empty(message: String)
    case failed(message: String, retryable: Bool)

    enum Kind {
        case personalized
        case coldStart
    }
}

extension MadeForYouShelfState: Equatable {
    static func == (lhs: MadeForYouShelfState, rhs: MadeForYouShelfState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.loading, .loading): return true
        case (.loaded(let lk, let lt), .loaded(let rk, let rt)):
            return lk == rk && lt.map(\.id) == rt.map(\.id)
        case (.empty(let lm), .empty(let rm)): return lm == rm
        case (.failed(let lmsg, let lretry), .failed(let rmsg, let rretry)):
            return lmsg == rmsg && lretry == rretry
        default: return false
        }
    }
}

extension MadeForYouShelfState.Kind: Equatable {}

@MainActor
final class MadeForYouShelfStore: ObservableObject {
    @Published var state: MadeForYouShelfState = .idle

    private let db: DatabaseService
    private let tasteProfileStore: TasteProfileStore
    private var archiveService: InternetArchiveService?
    private let backfillVersionKey = "tasteProfileBackfillVersion"
    private let currentBackfillVersion = 1
    private var storeTask: Task<Void, Never>?

    init(db: DatabaseService, tasteProfileStore: TasteProfileStore) {
        self.db = db
        self.tasteProfileStore = tasteProfileStore
    }

    func setArchiveService(_ service: InternetArchiveService) {
        self.archiveService = service
    }

    private var isLoadable: Bool {
        switch state {
        case .idle, .empty, .failed: return true
        default: return false
        }
    }

    func loadIfNeeded() async {
        guard isLoadable else { return }

        state = .loading
        await ensureTasteBackfillIfNeeded()

        if let cached = await loadDailyCache(), !cached.isEmpty {
            var tracks: [Track] = []
            for id in cached {
                if let track = await db.fetchTrack(id: id) {
                    tracks.append(track)
                }
            }
            if !tracks.isEmpty {
                state = .loaded(.personalized, tracks)
                return
            }
        }

        let hasProfile = await tasteProfileStore.hasAnyProfile()
        var personalizedSuccess = false

        if hasProfile, let svc = archiveService {
            let controller = RecommendationsController(
                db: db, archiveService: svc, tasteStore: tasteProfileStore)
            if let recs = try? await controller.fetchMixedRecommendations(),
               recs.count >= RecommendationConstants.minShelf {
                let trackIds = recs.map(\.id)
                await saveDailyCache(trackIds: trackIds, source: "personalized")
                state = .loaded(.personalized, recs)
                personalizedSuccess = true
            }
        }

        if !personalizedSuccess {
            let coldTracks = await fetchColdStartPicks()
            if !coldTracks.isEmpty {
                let trackIds = coldTracks.map(\.id)
                await saveDailyCache(trackIds: trackIds, source: "cold_start")
                state = .loaded(.coldStart, coldTracks)
            } else {
                state = .empty(message: "Could not build your shelf right now.")
            }
        }
    }

    private func fetchColdStartPicks() async -> [Track] {
        guard let svc = archiveService else { return [] }
        let queries = [
            "mediatype:audio AND collection:(etree OR musopen OR 78rpm)",
            "mediatype:audio AND collection:librivoxaudio"
        ]
        var results: [Track] = []
        for query in queries {
            if let batch = try? await svc.fetchTracks(
                iaQuery: query, matchTags: ["for-you"], limit: 15
            ), !batch.isEmpty {
                results.append(contentsOf: batch)
            }
        }
        return Array(results.shuffled().prefix(RecommendationConstants.kTarget))
    }

    func ensureTasteBackfillIfNeeded() async {
        let version = UserDefaults.standard.integer(forKey: backfillVersionKey)
        guard version < currentBackfillVersion else { return }

        let hasProfile = await tasteProfileStore.hasAnyProfile()
        guard !hasProfile else {
            UserDefaults.standard.set(currentBackfillVersion, forKey: backfillVersionKey)
            return
        }

        let playedTracks = await db.fetchRecentlyPlayedTracksForTasteBackfill(limit: 200)
        guard !playedTracks.isEmpty else {
            UserDefaults.standard.set(currentBackfillVersion, forKey: backfillVersionKey)
            return
        }

        for track in playedTracks {
            await tasteProfileStore.seedFromTrack(track, channel: nil)
        }

        UserDefaults.standard.set(currentBackfillVersion, forKey: backfillVersionKey)
    }

    func invalidateForHistoryChange(version: Int) {
        state = .idle
    }

    func saveDailyCache(trackIds: [String], source: String) async {
        let day = Self.todayYYYYMMDD()
        await db.saveMadeForYouDailyCache(day: day, trackIds: trackIds, source: source)
    }

    func loadDailyCache() async -> [String]? {
        let day = Self.todayYYYYMMDD()
        let entries = await db.fetchMadeForYouDailyCache(day: day)
        guard !entries.isEmpty else { return nil }
        return entries.map { $0.trackId }
    }

    private static func todayYYYYMMDD() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
