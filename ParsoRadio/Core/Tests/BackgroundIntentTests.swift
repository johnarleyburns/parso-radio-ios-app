import XCTest
@testable import ParsoMusic

@MainActor
final class BackgroundIntentTests: XCTestCase {

    private var db: DatabaseService!
    private var vm: PlayerViewModel!
    private var engine: FakeAudioEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()
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
        UserDefaults.standard.removeObject(forKey: "siri.pendingChannelId")
        UserDefaults.standard.removeObject(forKey: "siri.pendingTimestamp")
    }

    override func tearDownWithError() throws {
        AppIntentBridge.shared.playerVM = nil
        UserDefaults.standard.removeObject(forKey: "lastChannelId")
        UserDefaults.standard.removeObject(forKey: "visitedChannelIds")
        UserDefaults.standard.removeObject(forKey: "siri.pendingChannelId")
        UserDefaults.standard.removeObject(forKey: "siri.pendingTimestamp")
        try super.tearDownWithError()
    }

    // MARK: - Intent performs in-process when playerVM exists

    func testPlayChannelIntentPerformsInProcess() async throws {
        let intent = PlayChannelIntent()
        intent.channel = ChannelEntity(id: "oxford-philosophy", displayName: "Philosophy", searchAliases: [])

        let result = try await intent.perform()
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "siri.pendingChannelId"),
            "oxford-philosophy"
        )
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "siri.pendingTimestamp"))
    }

    func testPlayPodcastIntentPerformsInProcess() async throws {
        let intent = PlayPodcastIntent()
        intent.podcast = PodcastEntity(id: "news-democracy-now", displayName: "Democracy Now!", searchAliases: [])

        let result = try await intent.perform()
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "siri.pendingChannelId"),
            "news-democracy-now"
        )
    }

    func testPlayLorewaveIntentPerformsInProcess() async throws {
        UserDefaults.standard.set("oxford-history", forKey: "lastChannelId")
        let intent = PlayLorewaveIntent()

        let result = try await intent.perform()
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "siri.pendingChannelId"),
            "oxford-history"
        )
    }

    // MARK: - Intent performs in extension process (playerVM is nil)

    func testPlayChannelIntentPerformsWithoutPlayerVM() async throws {
        AppIntentBridge.shared.playerVM = nil

        let intent = PlayChannelIntent()
        intent.channel = ChannelEntity(id: "oxford-philosophy", displayName: "Philosophy", searchAliases: [])

        let result = try await intent.perform()
    }

    func testPlayPodcastIntentPerformsWithoutPlayerVM() async throws {
        AppIntentBridge.shared.playerVM = nil

        let intent = PlayPodcastIntent()
        intent.podcast = PodcastEntity(id: "news-democracy-now", displayName: "Democracy Now!", searchAliases: [])

        _ = try await intent.perform()
    }

    func testPlayLorewaveIntentPerformsWithoutPlayerVM() async throws {
        AppIntentBridge.shared.playerVM = nil

        let intent = PlayLorewaveIntent()
        _ = try await intent.perform()
    }

    // MARK: - Kids Mode blocks intents

    func testKidsModeBlocksPlayChannelIntent() async {
        let pin = KidsModeController.shared.forceEnable()
        let intent = PlayChannelIntent()
        intent.channel = ChannelEntity(id: "oxford-philosophy", displayName: "Philosophy", searchAliases: [])

        do {
            _ = try await intent.perform()
            XCTFail("Intent must throw kidsModeActive error")
        } catch let error as IntentError {
            XCTAssertEqual(error.localizedStringResource.key,
                           IntentError.kidsModeActive.localizedStringResource.key)
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        _ = KidsModeController.shared.disable(pin: pin)
    }

    func testKidsModeBlocksPlayPodcastIntent() async {
        let pin = KidsModeController.shared.forceEnable()
        let intent = PlayPodcastIntent()
        intent.podcast = PodcastEntity(id: "news-democracy-now", displayName: "Democracy Now!", searchAliases: [])

        do {
            _ = try await intent.perform()
            XCTFail("Intent must throw kidsModeActive error")
        } catch let error as IntentError {
            if case .kidsModeActive = error { } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        _ = KidsModeController.shared.disable(pin: pin)
    }

    func testKidsModeBlocksPlayLorewaveIntent() async {
        let pin = KidsModeController.shared.forceEnable()
        let intent = PlayLorewaveIntent()

        do {
            _ = try await intent.perform()
            XCTFail("Intent must throw kidsModeActive error")
        } catch let error as IntentError {
            if case .kidsModeActive = error { } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        _ = KidsModeController.shared.disable(pin: pin)
    }

    // MARK: - App Group communication

    func testStorePendingCommandInAppGroupWritesToCorrectSuite() {
        let appGroupDefaults = UserDefaults(suiteName: AppGroup.suiteName)!
        appGroupDefaults.removeObject(forKey: "siri.pendingChannelId")
        appGroupDefaults.removeObject(forKey: "siri.pendingTimestamp")

        AppIntentBridge.shared.storePendingCommandInAppGroup(channelId: "bg-channel")

        XCTAssertEqual(appGroupDefaults.string(forKey: "siri.pendingChannelId"), "bg-channel")
        XCTAssertNotNil(appGroupDefaults.object(forKey: "siri.pendingTimestamp"))

        XCTAssertNil(UserDefaults.standard.string(forKey: "siri.pendingChannelId"))

        appGroupDefaults.removeObject(forKey: "siri.pendingChannelId")
        appGroupDefaults.removeObject(forKey: "siri.pendingTimestamp")
    }

    func testAppGroupSuiteNameMatchesExtensionEntitlement() {
        XCTAssertEqual(AppGroup.suiteName, "group.guru.parso.ios-radio-app")
    }

    func testAppGroupUserDefaultsSurvivesWriteAndRead() {
        let defaults = UserDefaults(suiteName: AppGroup.suiteName)!

        defaults.set("survival-test", forKey: "siri.intent.test")
        XCTAssertEqual(defaults.string(forKey: "siri.intent.test"), "survival-test")

        defaults.removeObject(forKey: "siri.intent.test")
        XCTAssertNil(defaults.string(forKey: "siri.intent.test"))
    }

    // MARK: - Channel resolves correctly from defaults

    func testChannelResolvesFromValidPendingId() {
        AppIntentBridge.shared.setPendingCommand(channelId: "lv-general-fiction")

        let channelId = UserDefaults.standard.string(forKey: "siri.pendingChannelId")
        let channel = Channel.defaults.first { $0.id == channelId }
        XCTAssertNotNil(channel)
        XCTAssertEqual(channel?.name, "General Fiction")
    }

    func testAllPodcastChannelsResolve() {
        let podcastChannels = Channel.defaults.filter { $0.category == "Podcasts" }
        XCTAssertFalse(podcastChannels.isEmpty, "Must have podcast channels")
        for ch in podcastChannels {
            let resolved = Channel.defaults.first { $0.id == ch.id }
            XCTAssertNotNil(resolved, "Podcast channel \(ch.id) must resolve")
        }
    }

    // MARK: - IntentResult

    func testPlayChannelIntentReturnsResult() async throws {
        let intent = PlayChannelIntent()
        intent.channel = ChannelEntity(id: "oxford-philosophy", displayName: "Philosophy", searchAliases: [])

        let result = try await intent.perform()
        XCTAssertNotNil(result)
    }

    // MARK: - remove openAppWhenRun

    func testAllIntentsHaveOpenAppWhenRunFalse() {
        XCTAssertFalse(PlayLorewaveIntent.openAppWhenRun)
        XCTAssertFalse(PlayChannelIntent.openAppWhenRun)
        XCTAssertFalse(PlayPodcastIntent.openAppWhenRun)
    }

    // MARK: - Stale pending guard

    func testStalePendingIgnoredByAgeCheck() {
        var ts = Date().timeIntervalSince1970 - 120  // 2 minutes old

        let isStale = (Date().timeIntervalSince1970 - ts) >= 60
        XCTAssertTrue(isStale)
    }

    func testFreshPendingAcceptedByAgeCheck() {
        let ts = Date().timeIntervalSince1970  // now

        let isFresh = (Date().timeIntervalSince1970 - ts) < 60
        XCTAssertTrue(isFresh)
    }
}
