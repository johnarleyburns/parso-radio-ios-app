import XCTest
@testable import ParsoMusic

@MainActor
final class PodcastSubscriptionStoreTests: XCTestCase {

    private var db: DatabaseService!
    private var store: PodcastSubscriptionStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        store = PodcastSubscriptionStore.shared
        store.resetForTesting()
    }

    override func tearDownWithError() throws {
        db = nil
        try super.tearDownWithError()
    }

    // MARK: - Safety

    func testStoreDoesNotCrashWithoutConfiguredDB() {
        // The store is safe to access even without a configured DB.
        // subscriptions is empty, add/remove are no-ops.
        let subs = store.subscriptions
        XCTAssertTrue(subs.isEmpty, "Should start with empty subscriptions")
    }

    func testStoreSubscriptionsEmptyBeforeConfigure() {
        // Before configure(db:) is called, subscriptions must be empty and
        // accessing properties must not crash (previously DatabaseService.shared
        // was accessed in init() which triggered fatalError on background threads).
        XCTAssertEqual(store.subscriptions.count, 0)
    }

    func testAddIsNoOpWithoutConfiguredDB() async {
        // add() is a no-op when db is not configured — must not crash.
        await store.add(name: "Test", feedURL: "https://example.com/feed.xml")
        XCTAssertTrue(store.subscriptions.isEmpty)
    }

    func testRemoveIsNoOpWithoutConfiguredDB() async {
        let sub = PodcastSubscription(
            id: "test", name: "Test", feedURL: "https://example.com/feed.xml",
            artworkURL: nil, createdAt: Date())
        await store.remove(sub)
        XCTAssertTrue(store.subscriptions.isEmpty)
    }

    // MARK: - Configured behavior

    func testConfigureLoadsSubscriptions() async throws {
        // When configured with a DatabaseService, subscriptions should load.
        store.configure(db: db)

        // Wait for async load
        try await Task.sleep(nanoseconds: 500_000_000)

        // Fresh DB — should be empty but loaded
        XCTAssertEqual(store.subscriptions.count, 0)
    }

    func testAddAndLoadAfterConfigure() async throws {
        store.configure(db: db)
        try await Task.sleep(nanoseconds: 500_000_000)

        await store.add(name: "NPR Up First", feedURL: "https://feeds.npr.org/510318/podcast.xml")
        XCTAssertEqual(store.subscriptions.count, 1)
        XCTAssertEqual(store.subscriptions.first?.name, "NPR Up First")
        XCTAssertEqual(store.subscriptions.first?.feedURL, "https://feeds.npr.org/510318/podcast.xml")
    }

    func testRemoveAfterConfigure() async throws {
        store.configure(db: db)
        try await Task.sleep(nanoseconds: 500_000_000)

        await store.add(name: "Test", feedURL: "https://example.com/feed.xml")
        XCTAssertEqual(store.subscriptions.count, 1)

        if let sub = store.subscriptions.first {
            await store.remove(sub)
        }
        XCTAssertEqual(store.subscriptions.count, 0)
    }

    func testChannelFromSubscription() {
        let sub = PodcastSubscription(
            id: "abc-123",
            name: "Test Podcast",
            feedURL: "https://example.com/feed.xml",
            artworkURL: nil,
            createdAt: Date()
        )
        let channel = store.channel(from: sub)

        XCTAssertEqual(channel.id, "podcast-abc-123")
        XCTAssertEqual(channel.name, "Test Podcast")
        XCTAssertEqual(channel.category, "Podcasts")
        XCTAssertEqual(channel.contentType, .spokenWord)
        XCTAssertEqual(channel.preferredSource, "podcast")
        XCTAssertEqual(channel.feedURL, "https://example.com/feed.xml")
        XCTAssertEqual(channel.tags, ["podcast-abc-123"])
    }

    func testChannelFromSubscriptionWithArtwork() {
        let sub = PodcastSubscription(
            id: "xyz-456",
            name: "Art Podcast",
            feedURL: "https://example.com/art.xml",
            artworkURL: "https://example.com/art.jpg",
            createdAt: Date()
        )
        let channel = store.channel(from: sub)

        XCTAssertEqual(channel.imageURL, "https://example.com/art.jpg")
    }

    func testConfigurePersistsAcrossMultipleCalls() async throws {
        // configure(db:) called multiple times should not crash or duplicate
        store.configure(db: db)
        store.configure(db: db)
        try await Task.sleep(nanoseconds: 500_000_000)

        await store.add(name: "One", feedURL: "https://one.example.com")
        await store.add(name: "Two", feedURL: "https://two.example.com")

        XCTAssertEqual(store.subscriptions.count, 2)
    }

    func testTaskCancelledOnReconfigure() async throws {
        store.configure(db: db)
        // Immediate reconfigure cancels previous task
        store.configure(db: db)
        try await Task.sleep(nanoseconds: 300_000_000)

        await store.add(name: "After Reconfig", feedURL: "https://example.com")
        XCTAssertEqual(store.subscriptions.count, 1)
    }

    func testChannelIdUsesPodcastPrefix() async throws {
        store.configure(db: db)
        _ = await store.add(name: "Test Pod", feedURL: "https://pod.example.com/feed")

        let sub = store.subscriptions.first!
        let channel = store.channel(from: sub)

        XCTAssertTrue(channel.id.hasPrefix("podcast-"),
            "Channel ID from subscription must use 'podcast-' prefix")
        XCTAssertTrue(channel.id.contains(sub.id),
            "Channel ID must embed the subscription's raw ID")
    }
}
