import XCTest
@testable import ParsoMusic

@MainActor
final class IntentsTests: XCTestCase {

    private var db: DatabaseService!
    private var vm: PlayerViewModel!
    private var engine: FakeAudioEngine!
    private let defaults = UserDefaults(suiteName: "IntentsTests")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults.removePersistentDomain(forName: "IntentsTests")
        db = try DatabaseService(path: ":memory:")
        engine = FakeAudioEngine()
        vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: engine,
            downloadManager: DownloadManager(db: db)
        )
        AppIntentBridge.shared.playerVM = vm
        UserDefaults.standard.removeObject(forKey: "lastChannelId")
        UserDefaults.standard.removeObject(forKey: "visitedChannelIds")
    }

    override func tearDownWithError() throws {
        AppIntentBridge.shared.playerVM = nil
        defaults.removePersistentDomain(forName: "IntentsTests")
        UserDefaults.standard.removeObject(forKey: "lastChannelId")
        UserDefaults.standard.removeObject(forKey: "visitedChannelIds")
        try super.tearDownWithError()
    }

    // MARK: - Entity query tests

    func testEntityQueryByIdentifier() async throws {
        let entities = try await ChannelEntityQuery().entities(for: ["guitar-classical"])
        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.id, "guitar-classical")
        XCTAssertEqual(entities.first?.displayName, "Classical Guitar")
    }

    func testEntityQueryByIdentifierMissing() async throws {
        let entities = try await ChannelEntityQuery().entities(for: ["does-not-exist"])
        XCTAssertTrue(entities.isEmpty)
    }

    func testEntityQueryMultipleIdentifiers() async throws {
        let entities = try await ChannelEntityQuery().entities(for: [
            "guitar-classical", "string-quartet", "does-not-exist"
        ])
        XCTAssertEqual(entities.count, 2)
        let ids = Set(entities.map(\.id))
        XCTAssertTrue(ids.contains("guitar-classical"))
        XCTAssertTrue(ids.contains("string-quartet"))
    }

    func testSuggestedEntitiesReturnsAllChannels() async throws {
        let entities = try await ChannelEntityQuery().suggestedEntities()
        XCTAssertEqual(entities.count, min(Channel.defaults.count, 40))
    }

    func testSuggestedEntitiesOrderVisitedFirst() async throws {
        UserDefaults.standard.set(["string-quartet", "piano-hour"], forKey: "visitedChannelIds")
        let entities = try await ChannelEntityQuery().suggestedEntities()
        XCTAssertEqual(entities.first?.id, "string-quartet")
        XCTAssertEqual(entities[1].id, "piano-hour")
    }

    func testSuggestedEntitiesCapped() async throws {
        let entities = try await ChannelEntityQuery().suggestedEntities()
        XCTAssertLessThanOrEqual(entities.count, 40)
    }

    func testSuggestedEntitiesNoDuplicates() async throws {
        UserDefaults.standard.set(["guitar-classical"], forKey: "visitedChannelIds")
        let entities = try await ChannelEntityQuery().suggestedEntities()
        let matches = entities.filter { $0.id == "guitar-classical" }
        XCTAssertEqual(matches.count, 1, "Visited channel must not appear twice")
    }

    func testPodcastEntityQueryOnlyReturnsPodcasts() async throws {
        let entities = try await PodcastEntityQuery().suggestedEntities()
        XCTAssertFalse(entities.isEmpty)
        for entity in entities {
            let ch = Channel.defaults.first { $0.id == entity.id }
            XCTAssertEqual(ch?.category, "Podcasts", "\(entity.displayName) must be Podcasts category, got \(ch?.category ?? "nil")")
        }
    }

    func testPodcastEntityQueryDecodesCorrectly() async throws {
        let entities = try await PodcastEntityQuery().entities(for: ["news-democracy-now"])
        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.displayName, "Democracy Now!")
    }

    func testPodcastEntityQueryExcludesNonPodcasts() async throws {
        let entities = try await PodcastEntityQuery().entities(for: ["guitar-classical"])
        XCTAssertTrue(entities.isEmpty, "Non-podcast channel must not appear in podcast query")
    }

    func testChannelEntityDisplayRepresentation() {
        let entity = ChannelEntity(id: "test-id", displayName: "Test Channel", searchAliases: [])
        let rep = entity.displayRepresentation
        XCTAssertEqual(String(localized: rep.title), "Test Channel")
    }

    func testPodcastEntityDisplayRepresentation() {
        let entity = PodcastEntity(id: "test-podcast", displayName: "Test Podcast", searchAliases: [])
        let rep = entity.displayRepresentation
        XCTAssertEqual(String(localized: rep.title), "Test Podcast")
    }

    // MARK: - Intent Bridge tests

    func testBridgeLoadChannelSetsPending() async {
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        await AppIntentBridge.shared.loadChannel(channel)

        XCTAssertEqual(UserDefaults.standard.string(forKey: "siri.pendingChannelId"), "guitar-classical")
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "siri.pendingTimestamp"))
    }

    func testBridgeResumePlaybackSetsPending() async {
        UserDefaults.standard.set("string-quartet", forKey: "lastChannelId")
        await AppIntentBridge.shared.resumePlayback()

        XCTAssertEqual(UserDefaults.standard.string(forKey: "siri.pendingChannelId"), "string-quartet")
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "siri.pendingTimestamp"))
    }

    func testBridgeSetPendingCommand() {
        AppIntentBridge.shared.setPendingCommand(channelId: "test-channel")

        XCTAssertEqual(UserDefaults.standard.string(forKey: "siri.pendingChannelId"), "test-channel")
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "siri.pendingTimestamp"))
    }

    func testBridgeStorePendingCommandInAppGroup() {
        let appGroupDefaults = UserDefaults(suiteName: AppGroup.suiteName)!
        appGroupDefaults.removeObject(forKey: "siri.pendingChannelId")
        appGroupDefaults.removeObject(forKey: "siri.pendingTimestamp")

        AppIntentBridge.shared.storePendingCommandInAppGroup(channelId: "appgroup-test")

        XCTAssertEqual(appGroupDefaults.string(forKey: "siri.pendingChannelId"), "appgroup-test")
        XCTAssertNotNil(appGroupDefaults.object(forKey: "siri.pendingTimestamp"))

        appGroupDefaults.removeObject(forKey: "siri.pendingChannelId")
        appGroupDefaults.removeObject(forKey: "siri.pendingTimestamp")
    }

    func testBridgeWithNilPlayerVM() async {
        AppIntentBridge.shared.playerVM = nil
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        await AppIntentBridge.shared.loadChannel(channel)
        // Must not crash when playerVM is nil
    }

    func testBridgeResumeWithNilPlayerVM() async {
        AppIntentBridge.shared.playerVM = nil
        await AppIntentBridge.shared.resumePlayback()
        // Must not crash when playerVM is nil
    }

    // MARK: - Kids Mode blocks

    func testKidsModeBlocksIntentBridge() async {
        let pin = KidsModeController.shared.forceEnable()
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        await AppIntentBridge.shared.loadChannel(channel)
        // Kids Mode on — bridge must refuse to load. Assert no channel change.
        XCTAssertNil(vm.currentChannel)
        _ = KidsModeController.shared.disable(pin: pin)
    }

    func testKidsModeBlocksResume() async {
        let pin = KidsModeController.shared.forceEnable()
        await AppIntentBridge.shared.resumePlayback()
        XCTAssertNil(vm.currentChannel)
        _ = KidsModeController.shared.disable(pin: pin)
    }

    // MARK: - Notification

    func testBridgePostsSiriNotificationOnLoadChannel() async {
        let expectation = self.expectation(forNotification: .siriIntentDidPerform, object: nil)
        expectation.isInverted = false

        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        await AppIntentBridge.shared.loadChannel(channel)

        await fulfillment(of: [expectation], timeout: 1)
    }

    func testBridgePostsSiriNotificationOnResume() async {
        let expectation = self.expectation(forNotification: .siriIntentDidPerform, object: nil)

        await AppIntentBridge.shared.resumePlayback()

        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: - Intent perform tests (in-process)

    func testPlayChannelIntentPerformWithPlayerVM() async throws {
        let intent = PlayChannelIntent()
        intent.channel = ChannelEntity(id: "guitar-classical", displayName: "Classical Guitar", searchAliases: [])

        let result = try await intent.perform()
        // In-process loads the channel
        let pendingId = UserDefaults.standard.string(forKey: "siri.pendingChannelId")
        XCTAssertEqual(pendingId, "guitar-classical")
    }

    func testPlayChannelIntentPerformChannelNotFound() async {
        let intent = PlayChannelIntent()
        intent.channel = ChannelEntity(id: "does-not-exist", displayName: "Missing", searchAliases: [])

        do {
            _ = try await intent.perform()
            XCTFail("Expected error for missing channel")
        } catch let error as IntentError {
            if case .channelNotFound(let name) = error {
                XCTAssertEqual(name, "Missing")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testPlayPodcastIntentPerformWithPlayerVM() async throws {
        let intent = PlayPodcastIntent()
        intent.podcast = PodcastEntity(id: "news-democracy-now", displayName: "Democracy Now!", searchAliases: [])

        let result = try await intent.perform()
        let pendingId = UserDefaults.standard.string(forKey: "siri.pendingChannelId")
        XCTAssertEqual(pendingId, "news-democracy-now")
    }

    func testPlayLorewaveIntentPerformWithPlayerVM() async throws {
        UserDefaults.standard.set("piano-hour", forKey: "lastChannelId")
        let intent = PlayLorewaveIntent()

        let result = try await intent.perform()
        let pendingId = UserDefaults.standard.string(forKey: "siri.pendingChannelId")
        XCTAssertEqual(pendingId, "piano-hour")
    }

    // MARK: - Intent static properties

    func testIntentsDoNotForceOpenApp() {
        XCTAssertFalse(PlayLorewaveIntent.openAppWhenRun)
        XCTAssertFalse(PlayChannelIntent.openAppWhenRun)
        XCTAssertFalse(PlayPodcastIntent.openAppWhenRun)
    }

    func testIntentTitlesNotEmpty() {
        XCTAssertFalse(PlayLorewaveIntent.title.key.isEmpty)
        XCTAssertFalse(PlayChannelIntent.title.key.isEmpty)
        XCTAssertFalse(PlayPodcastIntent.title.key.isEmpty)
    }

    // MARK: - App Group helpers

    func testAppGroupSuiteName() {
        XCTAssertEqual(AppGroup.suiteName, "group.guru.parso.ios-radio-app")
    }

    func testAppGroupUserDefaultsAccessible() {
        let defaults = UserDefaults.appGroup
        defaults.set("test-value", forKey: "siri-test")
        XCTAssertEqual(defaults.string(forKey: "siri-test"), "test-value")
        defaults.removeObject(forKey: "siri-test")
    }

    // MARK: - IntentError descriptions

    func testIntentErrorChannelNotFound() {
        let error = IntentError.channelNotFound("Test")
        let message = String(localized: error.localizedStringResource)
        XCTAssertTrue(message.contains("Test"))
    }

    func testIntentErrorKidsModeActive() {
        let error = IntentError.kidsModeActive
        let message = String(localized: error.localizedStringResource)
        XCTAssertFalse(message.isEmpty)
    }

    func testIntentErrorAppNotAvailable() {
        let error = IntentError.appNotAvailable
        let message = String(localized: error.localizedStringResource)
        XCTAssertFalse(message.isEmpty)
    }
}
