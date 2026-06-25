import Foundation

struct PodcastSubscription: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var feedURL: String
    var artworkURL: String?
    let createdAt: Date
}

@MainActor
final class PodcastSubscriptionStore: ObservableObject {
    static let shared = PodcastSubscriptionStore()

    @Published private(set) var subscriptions: [PodcastSubscription] = []

    private var db: DatabaseService?
    private var loadTask: Task<Void, Never>?

    private init() {}

    func configure(db: DatabaseService) {
        self.db = db
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadFromDB()
        }
    }

    func resetForTesting() {
        db = nil
        loadTask?.cancel()
        loadTask = nil
        subscriptions = []
    }

    private func loadFromDB() async {
        guard let db else { return }
        let loaded = await db.fetchPodcastSubscriptions()
        // A reconfigure cancels this task; don't let a stale load clobber the
        // current subscriptions (also prevents cross-test state contamination).
        guard !Task.isCancelled else { return }
        subscriptions = loaded
    }

    @discardableResult
    func add(name: String, feedURL: String, artworkURL: String? = nil) async -> Bool {
        await add(id: UUID().uuidString, name: name, feedURL: feedURL, artworkURL: artworkURL)
    }

    @discardableResult
    func add(id: String, name: String, feedURL: String, artworkURL: String? = nil) async -> Bool {
        guard let db else { return false }
        guard !subscriptions.contains(where: { $0.feedURL == feedURL }) else { return false }
        let sub = PodcastSubscription(
            id: id,
            name: name,
            feedURL: feedURL,
            artworkURL: artworkURL,
            createdAt: Date()
        )
        await db.savePodcastSubscription(sub)
        subscriptions.append(sub)
        return true
    }

    func remove(_ sub: PodcastSubscription) async {
        guard let db else { return }
        await db.deletePodcastSubscription(sub)
        subscriptions.removeAll { $0.id == sub.id }
    }

    func channel(from sub: PodcastSubscription) -> Channel {
        Channel(
            id: "podcast-\(sub.id)",
            name: sub.name,
            category: "Podcasts",
            icon: "antenna.radiowaves.left.and.right",
            tags: ["podcast-\(sub.id)"],
            contentType: .spokenWord,
            preferredSource: "podcast",
            feedURL: sub.feedURL,
            imageURL: sub.artworkURL
        )
    }
}
