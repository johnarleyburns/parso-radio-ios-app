import Foundation

/// Persists which podcast episode IDs have been heard, so QueueManager can skip
/// recently-heard episodes (30-day window). Stored in UserDefaults as JSON.
final class PodcastPlayHistory {
    private static let key = "podcast_play_history_v1"
    private static let windowDays: Double = 30

    struct Entry: Codable {
        let trackId: String
        let listenedAt: Date
    }

    static func markHeard(_ trackId: String) {
        var entries = load()
        entries.removeAll { $0.trackId == trackId }
        entries.append(Entry(trackId: trackId, listenedAt: Date()))
        save(entries)
    }

    // IDs heard within the last 30 days.
    static func recentlyHeardIds() -> Set<String> {
        let cutoff = Date().addingTimeInterval(-windowDays * 86400)
        return Set(load().filter { $0.listenedAt > cutoff }.map { $0.trackId })
    }

    static func evictExpired() {
        let cutoff = Date().addingTimeInterval(-windowDays * 86400)
        save(load().filter { $0.listenedAt > cutoff })
    }

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    private static func save(_ entries: [Entry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
