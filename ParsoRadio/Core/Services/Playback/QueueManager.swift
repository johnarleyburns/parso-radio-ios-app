import Foundation

final class QueueManager {
    private let db: DatabaseService
    private var recentIDs: [String] = []
    private let historyLimit = 50

    init(db: DatabaseService) {
        self.db = db
    }

    // Returns the next track that would be picked without advancing the queue.
    // Used for look-ahead URL pre-resolution while the current track is playing.
    func peekNextTrack(channel: Channel) async -> Track? {
        var pool = await db.fetchTracks(forChannel: channel)
            .filter { !recentIDs.contains($0.id) }
        if pool.isEmpty { return nil }
        return weightedRandom(from: pool, seed: dailySeed(for: channel) &+ 1)
    }

    func nextTrack(channel: Channel) async -> Track? {
        var pool = await db.fetchTracks(forChannel: channel)
            .filter { !recentIDs.contains($0.id) }

        // Expand to similar composers when pool is thin
        if pool.count < 20, !channel.composers.isEmpty {
            let expanded = channel.composers
                .flatMap { ComposerMap.similarity[$0] ?? [] }
            let expandedChannel = Channel(
                id: channel.id + "-expanded",
                name: channel.name,
                category: channel.category,
                icon: channel.icon,
                composers: expanded,
                instruments: channel.instruments,
                tags: channel.tags,
                isDownloaded: false
            )
            let extra = await db.fetchTracks(forChannel: expandedChannel)
                .filter { !recentIDs.contains($0.id) }
            pool.append(contentsOf: extra)
        }

        // Fallback to tag-only if still empty
        if pool.isEmpty {
            let tagChannel = Channel(
                id: channel.id + "-tag-fallback",
                name: channel.name,
                category: channel.category,
                icon: channel.icon,
                composers: [],
                instruments: [],
                tags: channel.tags,
                isDownloaded: false
            )
            pool = await db.fetchTracks(forChannel: tagChannel)
                .filter { !recentIDs.contains($0.id) }
        }

        guard !pool.isEmpty else { return nil }

        let track = weightedRandom(from: pool, seed: dailySeed(for: channel))
        record(track.id)
        return track
    }

    // MARK: - Private

    private func weightedRandom(from pool: [Track], seed: UInt64) -> Track {
        var rng = SeededRNG(seed: seed &+ UInt64(recentIDs.count))
        let totalWeight = pool.reduce(0.0) { $0 + ($1.qualityScore * $1.metadataConfidence) }
        guard totalWeight > 0 else { return pool[Int(rng.next() % UInt64(pool.count))] }

        var pick = Double(rng.next()) / Double(UInt64.max) * totalWeight
        for track in pool {
            pick -= track.qualityScore * track.metadataConfidence
            if pick <= 0 { return track }
        }
        return pool.last!
    }

    private func dailySeed(for channel: Channel) -> UInt64 {
        let dateStr = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        let raw = (dateStr + channel.id).utf8.reduce(UInt64(5381)) { ($0 &<< 5) &+ $0 &+ UInt64($1) }
        return raw
    }

    private func record(_ id: String) {
        recentIDs.append(id)
        if recentIDs.count > historyLimit {
            recentIDs.removeFirst()
        }
    }
}

// MARK: - Simple seeded RNG (xorshift64)

private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 1 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
