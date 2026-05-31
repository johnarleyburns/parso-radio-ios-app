import Foundation

final class QueueManager {
    private let db: DatabaseService
    // Per-channel "shadow recently played": the last `historyLimit` item ids
    // chosen for each channel are excluded from re-selection, so the channel
    // works through fresh material before repeating (the "too many repeats"
    // fix). PERSISTED across launches (UserDefaults) — an in-memory-only list
    // reset every cold start, which is why the same tracks kept coming back.
    // Per-channel (not shared) so one channel's history can't shrink another's.
    private var recentByChannel: [String: [String]] = [:]
    private let historyLimit = 30
    private static let persistKey = "queueManager.recentByChannel"
    // Injectable so unit tests get an isolated store instead of sharing the
    // process-wide standard defaults (which would couple test methods).
    private let defaults: UserDefaults
    // Curator Mode: a curated channel with a shipped (non-empty) manifest plays
    // its approved pool — explicit, human-approved tracks. Injectable so tests
    // don't depend on the bundled curation.json.
    private let manifestPool: (String) -> [Track]

    init(db: DatabaseService, defaults: UserDefaults = .standard,
         manifestPool: @escaping (String) -> [Track]
             = { LiveCurationStore.shared.pool(for: $0) }) {
        self.db = db
        self.defaults = defaults
        self.manifestPool = manifestPool
        if let stored = defaults.dictionary(forKey: Self.persistKey)
            as? [String: [String]] {
            recentByChannel = stored
        }
    }

    private func persist() {
        defaults.set(recentByChannel, forKey: Self.persistKey)
    }

    // Curated radio-style channels always shuffle regardless of the global
    // toggle: registry-backed IA channels and Lecture channels (which
    // aggregate a whole faculty). Sequential only makes sense for
    // podcast/news. Pure + static so it is deterministically unit-testable
    // without draining a seeded-random queue.
    static func usesShuffle(channel: Channel, shuffleMode: Bool) -> Bool {
        shuffleMode || channel.iaQueryEntry != nil || channel.category == "Lectures"
    }

    private func recents(_ channelId: String) -> [String] { recentByChannel[channelId] ?? [] }

    private func record(_ id: String, channelId: String) {
        var list = recentByChannel[channelId] ?? []
        list.removeAll { $0 == id }          // de-dupe → move to most-recent
        list.append(id)
        if list.count > historyLimit { list.removeFirst(list.count - historyLimit) }
        recentByChannel[channelId] = list
        persist()
    }

    // MARK: - Public

    func nextTrack(channel: Channel, shuffleMode: Bool) async -> Track? {
        await _next(channel: channel, shuffleMode: shuffleMode, record: true)
    }

    func peekNextTrack(channel: Channel, shuffleMode: Bool) async -> Track? {
        await _next(channel: channel, shuffleMode: shuffleMode, record: false)
    }

    // MARK: - Librivox sequential advance

    func nextPart(after track: Track, channel: Channel) async -> Track? {
        guard let parent = track.parentIdentifier,
              let currentPart = track.partNumber else { return nil }
        let allTracks = await db.fetchTracks(forChannel: channel)
        let parts = allTracks
            .filter { $0.parentIdentifier == parent }
            .sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        guard let nextPart = parts.first(where: { ($0.partNumber ?? 0) == currentPart + 1 }) else {
            // Last part — advance to first part of the next book
            return await nextBook(after: parent, channel: channel)
        }
        return nextPart
    }

    func previousPart(before track: Track, channel: Channel) async -> Track? {
        guard let parent = track.parentIdentifier,
              let currentPart = track.partNumber else { return nil }
        let allTracks = await db.fetchTracks(forChannel: channel)
        let parts = allTracks
            .filter { $0.parentIdentifier == parent }
            .sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        return parts.first(where: { ($0.partNumber ?? 0) == currentPart - 1 })
    }

    func firstPartOfNextBook(after track: Track, channel: Channel) async -> Track? {
        guard let parent = track.parentIdentifier else { return nil }
        return await nextBook(after: parent, channel: channel)
    }

    func firstPartOfPreviousBook(before track: Track, channel: Channel) async -> Track? {
        guard let parent = track.parentIdentifier else { return nil }
        return await previousBook(before: parent, channel: channel)
    }

    // MARK: - Private

    private func _next(channel: Channel, shuffleMode: Bool, record: Bool) async -> Track? {
        // Podcast/news channels: always sequential newest-first, 30-day dedup via DB
        if channel.feedURL != nil {
            return await nextPodcastTrack(channel: channel, record: record)
        }

        let recent = recents(channel.id)

        // CURATOR MODE: a channel with non-empty curation plays its approved
        // pool ONLY — no search, no composer-expand, the explicit human-
        // approved list. See CURATOR-MODE-PLAN.md.
        //
        // Manifest-only enforcement for the Curated category: regardless of
        // whether the pool has entries yet, a "Curated" channel NEVER falls
        // back to the search pool. While an uncurated Curated channel will be
        // empty (return nil here → "no track" upstream), this is the user's
        // explicit choice ("die on the hill" of curated quality) and it makes
        // the on-device live-curation feedback loop work: as the curator
        // approves tracks, the channel populates LIVE without an app rebuild.
        let curated = manifestPool(channel.id)
        // Only enforce manifest-only on SHIPPED Curated channels (those with
        // an `iaQueryEntry` in the registry). Test fixtures like
        // `Channel.fmaJazzTestChannel` reuse the "Curated" category for legacy
        // reasons but have no registry entry — they keep their tag-based
        // search-pool fallback.
        let isCuratedCategory =
            (channel.category == "Curated" && channel.iaQueryEntry != nil)
        if !curated.isEmpty {
            var approvedPool = curated.filter { !recent.contains($0.id) }
            if approvedPool.isEmpty {            // cycled all → reset, replay
                recentByChannel[channel.id] = []
                persist()
                approvedPool = curated
            }
            let pick: Track
            if Self.usesShuffle(channel: channel, shuffleMode: shuffleMode) {
                pick = weightedRandom(from: approvedPool,
                                      seed: dailySeed(for: channel),
                                      variance: recent.count)
            } else {
                pick = approvedPool.sorted {
                    ($0.addedDate ?? .distantPast) > ($1.addedDate ?? .distantPast)
                }.first!
            }
            if record { self.record(pick.id, channelId: channel.id) }
            return pick
        }

        // Curated category, no approvals yet → return nil (channel empty
        // until the curator approves something). Non-Curated channels fall
        // through to the search pool below.
        if isCuratedCategory { return nil }

        // Only a book/album's FIRST track is eligible in a channel: a
        // multi-part item plays its opening track and the user adds the whole
        // book to a playlist if they want it — the channel never cycles
        // through one book's chapters.
        var pool = await db.fetchTracks(forChannel: channel)
            .filter { !recent.contains($0.id) && ($0.partNumber ?? 1) <= 1 }

        // Expand pool if thin (composer channels only — never touches the
        // isolation of curated/registry channels, which have no composers).
        if pool.count < 20, !channel.composers.isEmpty {
            let similar = channel.composers.flatMap { ComposerMap.similarity[$0] ?? [] }
            let expanded = Channel(
                id: channel.id + "-expanded", name: channel.name,
                category: channel.category, icon: channel.icon,
                composers: similar, instruments: channel.instruments,
                tags: channel.tags, contentType: channel.contentType
            )
            let extra = await db.fetchTracks(forChannel: expanded)
                .filter { !recent.contains($0.id) }
            pool.append(contentsOf: extra)
        }
        // Channel exhausted: loop it. Re-fetch the SAME channel (preferredSource
        // + stamp/tag isolation intact) — never a generic non-isolated
        // fallback, which used to leak other channels' tracks in.
        if pool.isEmpty {
            recentByChannel[channel.id] = []
            persist()
            pool = await db.fetchTracks(forChannel: channel)
                .filter { ($0.partNumber ?? 1) <= 1 }
        }
        guard !pool.isEmpty else { return nil }

        // Curated radio-style channels always play in random order regardless
        // of the global shuffle toggle:
        //  - registry-backed IA channels (e.g. Spanish Guitar), and
        //  - Lecture channels, which aggregate every series in a faculty, so a
        //    random mix is the intended experience (not one course in order;
        //    Oxford tracks also carry no addedDate, so the non-shuffle path
        //    would just emit an arbitrary DB order anyway).
        // Sequential newest-first only makes sense for podcast/news channels.
        let effectiveShuffle = Self.usesShuffle(channel: channel, shuffleMode: shuffleMode)

        let track: Track
        if effectiveShuffle {
            track = weightedRandom(from: pool,
                                   seed: dailySeed(for: channel),
                                   variance: recent.count)
        } else {
            // Recent-first: sort by addedDate DESC, fall back to qualityScore
            let sorted = pool.sorted {
                let d0 = $0.addedDate ?? Date(timeIntervalSince1970: $0.qualityScore)
                let d1 = $1.addedDate ?? Date(timeIntervalSince1970: $1.qualityScore)
                return d0 > d1
            }
            track = sorted.first!
        }
        if record { self.record(track.id, channelId: channel.id) }
        return track
    }

    private func nextPodcastTrack(channel: Channel, record shouldRecord: Bool) async -> Track? {
        let heard = await db.recentlyHeardIds(forChannel: channel.id)
        let recent = recents(channel.id)
        let pool = await db.fetchTracks(forChannel: channel)
            .filter { !heard.contains($0.id) && !recent.contains($0.id) }
        guard let track = pool.first else { return nil }
        if shouldRecord {
            self.record(track.id, channelId: channel.id)
            await db.recordPlayed(channelId: channel.id, trackId: track.id)
        }
        return track
    }

    // Returns the first track of the next distinct parentIdentifier group
    private func nextBook(after parentId: String, channel: Channel) async -> Track? {
        let all = await db.fetchTracks(forChannel: channel)
        let parents = orderedParents(from: all)
        guard let idx = parents.firstIndex(of: parentId),
              idx + 1 < parents.count else {
            // Wrap to first book
            return firstPart(of: parents.first ?? "", in: all)
        }
        return firstPart(of: parents[idx + 1], in: all)
    }

    private func previousBook(before parentId: String, channel: Channel) async -> Track? {
        let all = await db.fetchTracks(forChannel: channel)
        let parents = orderedParents(from: all)
        guard let idx = parents.firstIndex(of: parentId), idx > 0 else {
            return firstPart(of: parents.last ?? "", in: all)
        }
        return firstPart(of: parents[idx - 1], in: all)
    }

    private func orderedParents(from tracks: [Track]) -> [String] {
        var seen = Set<String>()
        return tracks.compactMap { $0.parentIdentifier }.filter { seen.insert($0).inserted }
    }

    private func firstPart(of parentId: String, in tracks: [Track]) -> Track? {
        tracks.filter { $0.parentIdentifier == parentId }
              .min(by: { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) })
    }

    // Items confirmed to belong to a multi-file album/book are boosted: in
    // curated channels these are typically higher-quality full releases, so
    // they should surface more often than one-off single tracks. nil (not yet
    // probed) and false stay neutral, so this only ever lifts known albums.
    static let albumBoost = 2.5

    static func selectionWeight(_ t: Track) -> Double {
        let base = t.qualityScore * max(t.metadataConfidence, 0.01)
        return base * (t.isMultiPart == true ? albumBoost : 1.0)
    }

    // `variance` (the channel's recent-play count) perturbs the daily seed so
    // successive picks within a session differ while staying reproducible.
    private func weightedRandom(from pool: [Track], seed: UInt64, variance: Int) -> Track {
        var rng = SeededRNG(seed: seed &+ UInt64(variance))
        let totalWeight = pool.reduce(0.0) { $0 + Self.selectionWeight($1) }
        guard totalWeight > 0 else { return pool[Int(rng.next() % UInt64(pool.count))] }
        var pick = Double(rng.next()) / Double(UInt64.max) * totalWeight
        for track in pool {
            pick -= Self.selectionWeight(track)
            if pick <= 0 { return track }
        }
        var fallback = SeededRNG(seed: seed &+ UInt64(variance) &+ 1)
        return pool[Int(fallback.next() % UInt64(pool.count))]
    }

    private func dailySeed(for channel: Channel) -> UInt64 {
        let dateStr = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        return (dateStr + channel.id).utf8.reduce(UInt64(5381)) { ($0 &<< 5) &+ $0 &+ UInt64($1) }
    }

}

// MARK: - Simple seeded RNG (xorshift64)

private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state
    }
}
