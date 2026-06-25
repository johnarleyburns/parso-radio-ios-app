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
    private let currentBackfillVersion = 3
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

    private var isLoaded: Bool {
        if case .loaded = state { return true }
        return false
    }

    /// The `playHistoryVersion` the current shelf content was built from. `-1`
    /// means "never loaded this session".
    private var lastLoadedHistoryVersion = -1

    /// Builds (or rebuilds) the shelf. The shelf is a *discovery* surface, so it
    /// excludes everything in your listening history (seen/surfaced) and rebuilds
    /// after every play — passing the current `playHistoryVersion` so each new
    /// track/audiobook reshapes the picks. Rapid plays coalesce because SwiftUI
    /// cancels the prior `.task(id:)` before starting the next.
    func loadIfNeeded(historyVersion: Int = 0) async {
        let historyChanged = historyVersion != lastLoadedHistoryVersion
        // Already showing content and nothing new was played → keep it.
        if !historyChanged, !isLoadable { return }

        let isFirstLoad = lastLoadedHistoryVersion == -1
        lastLoadedHistoryVersion = historyVersion
        // Only the genuine first load of the session may reuse the daily cache;
        // any play invalidates it so the shelf reflects fresh taste.
        await rebuild(useCache: isFirstLoad && historyVersion == 0)
    }

    private func rebuild(useCache: Bool) async {
        // Keep existing picks visible while refreshing; only spin when empty.
        if !isLoaded { state = .loading }
        await ensureTasteBackfillIfNeeded()

        if useCache, let cached = await loadDailyCache(), !cached.isEmpty {
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

    /// Defensive media-kind backstop (the primary guard is query-side scoping in
    /// RecommendationQueryBuilder). Music keeps only tracks that classify as
    /// music; Books drops podcast/lecture sources but keeps LibriVox items —
    /// cold-start audiobook picks carry the generic `for-you` stamp and so
    /// classify as `.music` under `inferredMediaKind`, hence the lenient rule.
    private func filtered(_ tracks: [Track]) -> [Track] {
        switch shelf {
        case .music:
            return tracks.filter { $0.inferredMediaKind == .music }
        case .books:
            return tracks.filter { $0.source != "podcast" && $0.source != "oxford_lectures" }
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
            iaQuery: query, matchTags: ["for-you"], limit: 25
        ), !batch.isEmpty {
            results.append(contentsOf: batch)
        }
        // Discovery surface: never surface anything already in listening history.
        let seen = await tasteProfileStore.fetchSeenIdentifiers()
        let surfaced = await tasteProfileStore.fetchSurfacedIdentifiers()
        let exclude = seen.union(surfaced)
        let fresh = filtered(results).filter { !isExcluded($0, exclude: exclude) }
        return Array(fresh.shuffled().prefix(RecommendationConstants.kTarget))
    }

    private func isExcluded(_ track: Track, exclude: Set<String>) -> Bool {
        if exclude.contains(track.id) { return true }
        let workKey = tasteProfileStore.workKeyFor(track)
        if workKey != track.id, exclude.contains(workKey) { return true }
        if let parent = track.parentIdentifier, !parent.isEmpty,
           parent != workKey, exclude.contains(parent) { return true }
        return false
    }

    func ensureTasteBackfillIfNeeded() async {
        let version = UserDefaults.standard.integer(forKey: backfillVersionKey)
        guard version < currentBackfillVersion else { return }

        if version >= 1 {
            // Existing user whose v1 backfill seeded with `channel: nil` — every
            // audiobook play was mis-bucketed into `music` and the `spoken`
            // bucket is empty. Rebuild both buckets from authoritative history.
            await migrateTasteProfileV2()
            UserDefaults.standard.set(currentBackfillVersion, forKey: backfillVersionKey)
            return
        }

        // version == 0: fresh install or pre-backfill upgrade. Only seed from
        // history when no profile exists yet (onboarding seeds it otherwise).
        let hasProfile = await tasteProfileStore.hasAnyProfile()
        guard !hasProfile else {
            UserDefaults.standard.set(currentBackfillVersion, forKey: backfillVersionKey)
            return
        }

        let played = await db.fetchRecentlyPlayedWithChannel(limit: 200)
        guard !played.isEmpty else {
            UserDefaults.standard.set(currentBackfillVersion, forKey: backfillVersionKey)
            return
        }

        for (track, channelId) in played {
            await tasteProfileStore.seedFromTrack(track, channel: Self.resolveChannel(channelId))
        }

        UserDefaults.standard.set(currentBackfillVersion, forKey: backfillVersionKey)
    }

    /// Clean rebuild of the taste profile from authoritative play history,
    /// preserving onboarding/favorite emphasis. Steps:
    ///   1. Snapshot the (polluted) music bucket.
    ///   2. Clear all taste terms.
    ///   3. Re-seed both buckets from `track_play_history` with channel-aware
    ///      classification — audiobook plays now land in `spoken`.
    ///   4. Restore the residual music weight (snapshot minus the rebuilt
    ///      play-derived weight) for terms that are NOT audiobook-origin (i.e.
    ///      absent from the rebuilt `spoken` bucket). That residual is the
    ///      onboarding/favorite emphasis, which has no play-history rows.
    func migrateTasteProfileV2() async {
        let snapshot = await db.fetchTasteProfileTerms(bucket: "music")

        await db.clearTasteProfileTerms()

        let played = await db.fetchRecentlyPlayedWithChannel(limit: 200)
        for (track, channelId) in played {
            await tasteProfileStore.seedFromTrack(track, channel: Self.resolveChannel(channelId))
        }

        // Harvest authoritative audiobook-listen records into `spoken` — this
        // catches books played from surfaces (shelf / search / direct) that
        // recorded no spoken channel, so prior book listening still counts.
        for entry in await db.fetchBookListenedEntries() {
            let author = (entry.author ?? "").trimmingCharacters(in: .whitespaces)
            if !author.isEmpty, author != "Unknown", author != "Various" {
                await tasteProfileStore.upsertTerm(bucket: "spoken", axis: "creator",
                                                   term: author.lowercased(), increment: 1.0)
            }
            for subject in (entry.subjects ?? "").split(separator: ",") {
                let s = subject.lowercased().trimmingCharacters(in: .whitespaces)
                if !s.isEmpty, !RecommendationConstants.subjectStopList.contains(s) {
                    await tasteProfileStore.upsertTerm(bucket: "spoken", axis: "subject",
                                                       term: s, increment: 1.0)
                }
            }
        }

        let rebuiltMusic = await db.fetchTasteProfileTerms(bucket: "music")
        let rebuiltSpoken = await db.fetchTasteProfileTerms(bucket: "spoken")

        var musicWeight: [String: Double] = [:]
        for t in rebuiltMusic { musicWeight["\(t.axis)|\(t.term)", default: 0] += t.weight }
        let spokenKeys = Set(rebuiltSpoken.map { "\($0.axis)|\($0.term)" })

        for term in snapshot {
            let key = "\(term.axis)|\(term.term)"
            // Audiobook-origin terms now live in `spoken`; never restore them to music.
            if spokenKeys.contains(key) { continue }
            let residual = term.weight - (musicWeight[key] ?? 0)
            if residual > 0.5 {
                await tasteProfileStore.upsertTerm(bucket: "music", axis: term.axis,
                                                    term: term.term, increment: residual)
            }
        }
    }

    /// Resolve the channel a track was played in from a stored play-history
    /// `channelId`. Registry channels carry their content kind (Audiobooks /
    /// Lectures / Podcasts); synthetic contexts (`direct`, playlist keys,
    /// user collections) return `nil` so seeding falls back to track signals.
    static func resolveChannel(_ channelId: String) -> Channel? {
        Channel.defaults.first { $0.id == channelId }
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
