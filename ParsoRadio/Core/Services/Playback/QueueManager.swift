import Foundation

final class QueueManager {
    private let db: DatabaseService
    private var recentByChannel: [String: [String]] = [:]
    private let historyLimit = 30
    private static let persistKey = "queueManager.recentByChannel"
    private let defaults: UserDefaults

    init(db: DatabaseService, defaults: UserDefaults = .standard) {
        self.db = db
        self.defaults = defaults
        if let stored = defaults.dictionary(forKey: Self.persistKey)
            as? [String: [String]] {
            recentByChannel = stored
        }
    }

    private func persist() {
        defaults.set(recentByChannel, forKey: Self.persistKey)
    }

    static func effectiveQueueStyle(_ channel: Channel, shuffleMode: Bool) -> PlaybackBehavior.QueueStyle {
        if channel.feedURL != nil { return .sequentialNewestFirst }
        if shuffleMode { return .shuffledPool }
        if channel.iaQueryEntry != nil { return .shuffledPool }
        return .sequentialInOrder
    }

    static func usesShuffle(channel: Channel, shuffleMode: Bool) -> Bool {
        effectiveQueueStyle(channel, shuffleMode: shuffleMode) == .shuffledPool
    }

    private func recents(_ channelId: String) -> [String] { recentByChannel[channelId] ?? [] }

    private func record(_ id: String, channelId: String) {
        var list = recentByChannel[channelId] ?? []
        list.removeAll { $0 == id }
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
        let parent = track.parentIdentifier ?? track.id
        let currentPart = track.partNumber ?? 1
        let allTracks = await db.fetchTracks(forChannel: channel)
        let parts = allTracks
            .filter { $0.parentIdentifier == parent }
            .sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        guard let nextPart = parts.first(where: { ($0.partNumber ?? 0) == currentPart + 1 }) else {
            if parts.isEmpty { return nil }
            return await nextBook(after: parent, channel: channel)
        }
        return nextPart
    }

    func previousPart(before track: Track, channel: Channel) async -> Track? {
        let parent = track.parentIdentifier ?? track.id
        let currentPart = track.partNumber ?? 1
        let allTracks = await db.fetchTracks(forChannel: channel)
        let parts = allTracks
            .filter { $0.parentIdentifier == parent }
            .sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        if parts.isEmpty { return nil }
        return parts.first(where: { ($0.partNumber ?? 0) == currentPart - 1 })
    }

    func firstPartOfNextBook(after track: Track, channel: Channel) async -> Track? {
        let parent = track.parentIdentifier ?? track.id
        return await nextBook(after: parent, channel: channel)
    }

    func firstPartOfPreviousBook(before track: Track, channel: Channel) async -> Track? {
        let parent = track.parentIdentifier ?? track.id
        return await previousBook(before: parent, channel: channel)
    }

    // MARK: - Private

    private func _next(channel: Channel, shuffleMode: Bool, record: Bool) async -> Track? {
        if channel.feedURL != nil {
            return await nextPodcastTrack(channel: channel, record: record)
        }

        let recent = recents(channel.id)

        var pool = await db.fetchTracks(forChannel: channel)
            .filter { !recent.contains($0.id) && ($0.partNumber ?? 1) <= 1 }

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
        if pool.isEmpty {
            recentByChannel[channel.id] = []
            persist()
            pool = await db.fetchTracks(forChannel: channel)
                .filter { ($0.partNumber ?? 1) <= 1 }
        }
        guard !pool.isEmpty else { return nil }

        let effectiveShuffle = Self.effectiveQueueStyle(channel, shuffleMode: shuffleMode) == .shuffledPool

        let track: Track
        if effectiveShuffle {
            track = weightedRandom(from: pool,
                                   seed: dailySeed(for: channel),
                                   variance: recent.count)
        } else {
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

    private func nextBook(after parentId: String, channel: Channel) async -> Track? {
        let all = await db.fetchTracks(forChannel: channel)
        let parents = orderedParents(from: all)
        guard let idx = parents.firstIndex(of: parentId),
              idx + 1 < parents.count else {
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

    static let albumBoost = 2.5

    static func selectionWeight(_ t: Track) -> Double {
        let base = t.qualityScore * max(t.metadataConfidence, 0.01)
        return base * (t.isMultiPart == true ? albumBoost : 1.0)
    }

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
