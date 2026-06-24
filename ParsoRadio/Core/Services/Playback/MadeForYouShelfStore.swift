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
    /// Which recommendation shelf this store powers. Drives the recommendation
    /// bucket, cold-start collections, the source filter, the daily-cache
    /// namespace, and the empty-state copy.
    enum Shelf {
        case music
        case books
    }

    @Published var state: MadeForYouShelfState = .idle

    private let db: DatabaseService
    private let tasteProfileStore: TasteProfileStore
    private let shelf: Shelf
    private var archiveService: InternetArchiveService?
    private let backfillVersionKey = "tasteProfileBackfillVersion"
    private let currentBackfillVersion = 1
    private var storeTask: Task<Void, Never>?

    init(db: DatabaseService, tasteProfileStore: TasteProfileStore, shelf: Shelf = .music) {
        self.db = db
        self.tasteProfileStore = tasteProfileStore
        self.shelf = shelf
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
            tracks = filtered(tracks)
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
            if let recs = try? await controller.fetchMixedRecommendations(
                musicOnly: shelf == .music, booksOnly: shelf == .books) {
                let picks = filtered(recs)
                if picks.count >= RecommendationConstants.minShelf {
                    let trackIds = picks.map(\.id)
                    await saveDailyCache(trackIds: trackIds, source: "personalized")
                    state = .loaded(.personalized, picks)
                    personalizedSuccess = true
                }
            }
        }

        if !personalizedSuccess {
            let coldTracks = await fetchColdStartPicks()
            if !coldTracks.isEmpty {
                let trackIds = coldTracks.map(\.id)
                await saveDailyCache(trackIds: trackIds, source: "cold_start")
                state = .loaded(.coldStart, coldTracks)
            } else {
                state = .empty(message: shelf == .books
                    ? "Couldn't load books right now."
                    : "Couldn't load music right now.")
            }
        }
    }

    /// Defensive source filter. Music drops spoken-word sources (podcast /
    /// lecture); Books drops podcasts (LibriVox audiobooks are kept).
    private func filtered(_ tracks: [Track]) -> [Track] {
        switch shelf {
        case .music:
            return tracks.filter { $0.source != "podcast" && $0.source != "oxford_lectures" }
        case .books:
            return tracks.filter { $0.source != "podcast" }
        }
    }

    private func fetchColdStartPicks() async -> [Track] {
        guard let svc = archiveService else { return [] }
        let query: String
        switch shelf {
        case .music:
            query = "mediatype:audio AND collection:(etree OR musopen OR 78rpm)"
        case .books:
            query = "mediatype:audio AND collection:librivoxaudio"
        }
        var results: [Track] = []
        if let batch = try? await svc.fetchTracks(
            iaQuery: query, matchTags: ["for-you"], limit: 15
        ), !batch.isEmpty {
            results.append(contentsOf: batch)
        }
        return Array(filtered(results).shuffled().prefix(RecommendationConstants.kTarget))
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
        await db.saveMadeForYouDailyCache(day: cacheDayKey(), trackIds: trackIds, source: source)
    }

    func loadDailyCache() async -> [String]? {
        let entries = await db.fetchMadeForYouDailyCache(day: cacheDayKey())
        guard !entries.isEmpty else { return nil }
        return entries.map { $0.trackId }
    }

    /// Namespaced per shelf so the music and books shelves never overwrite each
    /// other's daily cache. Music keeps the bare date key (backward compatible).
    private func cacheDayKey() -> String {
        let day = Self.todayYYYYMMDD()
        switch shelf {
        case .music: return day
        case .books: return "books:\(day)"
        }
    }

    private static func todayYYYYMMDD() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
