import Foundation

struct PodcastSubscription: Identifiable, Codable, Equatable {
    let id: String          // UUID
    var name: String        // User-displayed name
    var feedURL: String     // RSS feed URL
    let createdAt: Date
}

@MainActor
final class PodcastSubscriptionStore: ObservableObject {
    static let shared = PodcastSubscriptionStore()

    @Published private(set) var subscriptions: [PodcastSubscription] = []

    private init() {
        Task { await loadFromDB() }
    }

    private func loadFromDB() async {
        subscriptions = await DatabaseService.shared.fetchPodcastSubscriptions()
    }

    func add(name: String, feedURL: String) async {
        let sub = PodcastSubscription(
            id: UUID().uuidString,
            name: name,
            feedURL: feedURL,
            createdAt: Date()
        )
        await DatabaseService.shared.savePodcastSubscription(sub)
        subscriptions.append(sub)
    }

    func remove(_ sub: PodcastSubscription) async {
        await DatabaseService.shared.deletePodcastSubscription(sub)
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
            feedURL: sub.feedURL
        )
    }
}
