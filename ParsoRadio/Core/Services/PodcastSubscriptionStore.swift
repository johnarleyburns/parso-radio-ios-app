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
        subscriptions = await db.fetchPodcastSubscriptions()
    }

    func add(name: String, feedURL: String, artworkURL: String? = nil) async {
        guard let db else { return }
        let sub = PodcastSubscription(
            id: UUID().uuidString,
            name: name,
            feedURL: feedURL,
            artworkURL: artworkURL,
            createdAt: Date()
        )
        await db.savePodcastSubscription(sub)
        subscriptions.append(sub)
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
