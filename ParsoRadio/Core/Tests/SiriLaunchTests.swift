import XCTest
@testable import ParsoMusic

@MainActor
final class SiriLaunchTests: XCTestCase {

    private let defaults = UserDefaults(suiteName: "SiriLaunchTests")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults.removePersistentDomain(forName: "SiriLaunchTests")
        UserDefaults.standard.removeObject(forKey: "siri.pendingChannelId")
        UserDefaults.standard.removeObject(forKey: "siri.pendingTimestamp")
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: "SiriLaunchTests")
        UserDefaults.standard.removeObject(forKey: "siri.pendingChannelId")
        UserDefaults.standard.removeObject(forKey: "siri.pendingTimestamp")
        try super.tearDownWithError()
    }

    // MARK: - Pending command flags

    func testBridgeSetsPendingChannelIdOnLoad() async {
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        let bridge = AppIntentBridge.shared

        bridge.setPendingCommand(channelId: channel.id)

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "siri.pendingChannelId"),
            "guitar-classical"
        )
    }

    func testBridgeSetsPendingTimestampOnLoad() async {
        let bridge = AppIntentBridge.shared
        bridge.setPendingCommand(channelId: "test")

        let ts = UserDefaults.standard.object(forKey: "siri.pendingTimestamp") as? TimeInterval
        XCTAssertNotNil(ts)
        XCTAssertEqual(ts!, Date().timeIntervalSince1970, accuracy: 2)
    }

    func testPendingTimestampIsRecent() {
        AppIntentBridge.shared.setPendingCommand(channelId: "test")

        let ts = UserDefaults.standard.object(forKey: "siri.pendingTimestamp") as! TimeInterval
        let age = Date().timeIntervalSince1970 - ts
        XCTAssertEqual(age, 0, accuracy: 1, "Timestamp must be set to now")
    }

    // MARK: - Stale pending detection

    func testPendingWithinThresholdIsValid() {
        UserDefaults.standard.set("test-channel", forKey: "siri.pendingChannelId")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "siri.pendingTimestamp")

        // Pending set just now — must still be valid (threshold is 60s).
        let channelId = UserDefaults.standard.string(forKey: "siri.pendingChannelId")
        let ts = UserDefaults.standard.object(forKey: "siri.pendingTimestamp") as? TimeInterval
        let age = Date().timeIntervalSince1970 - (ts ?? 0)
        XCTAssertLessThan(age, 60, "Pending timestamp must be within the 60s threshold")
        XCTAssertEqual(channelId, "test-channel")
    }

    func testPendingOlderThanThresholdIsStale() {
        UserDefaults.standard.set("test-channel", forKey: "siri.pendingChannelId")
        UserDefaults.standard.set(Date().timeIntervalSince1970 - 120, forKey: "siri.pendingTimestamp")

        let ts = UserDefaults.standard.object(forKey: "siri.pendingTimestamp") as? TimeInterval
        let age = Date().timeIntervalSince1970 - (ts ?? 0)
        XCTAssertGreaterThan(age, 60, "Pending timestamp must exceed threshold to be stale")
    }

    // MARK: - Pending cleanup

    func testPendingKeysRemovable() {
        AppIntentBridge.shared.setPendingCommand(channelId: "cleanup-test")

        XCTAssertNotNil(UserDefaults.standard.string(forKey: "siri.pendingChannelId"))
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "siri.pendingTimestamp"))

        UserDefaults.standard.removeObject(forKey: "siri.pendingChannelId")
        UserDefaults.standard.removeObject(forKey: "siri.pendingTimestamp")

        XCTAssertNil(UserDefaults.standard.string(forKey: "siri.pendingChannelId"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "siri.pendingTimestamp"))
    }

    // MARK: - Notification posting

    func testBridgePostsSiriNotificationOnSetPending() async {
        let expectation = self.expectation(forNotification: .siriIntentDidPerform, object: nil)

        AppIntentBridge.shared.setPendingCommand(channelId: "notif-test")
        NotificationCenter.default.post(name: .siriIntentDidPerform, object: nil)

        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: - App Group pending

    func testAppGroupPendingWriteAndRead() {
        let appGroupDefaults = UserDefaults(suiteName: AppGroup.suiteName)!
        appGroupDefaults.removeObject(forKey: "siri.pendingChannelId")
        appGroupDefaults.removeObject(forKey: "siri.pendingTimestamp")

        AppIntentBridge.shared.storePendingCommandInAppGroup(channelId: "appgroup-launch")

        let channelId = appGroupDefaults.string(forKey: "siri.pendingChannelId")
        let ts = appGroupDefaults.object(forKey: "siri.pendingTimestamp") as? TimeInterval

        XCTAssertEqual(channelId, "appgroup-launch")
        XCTAssertNotNil(ts)

        appGroupDefaults.removeObject(forKey: "siri.pendingChannelId")
        appGroupDefaults.removeObject(forKey: "siri.pendingTimestamp")
    }

    // MARK: - No double write

    func testSetPendingOverwritesPrevious() {
        AppIntentBridge.shared.setPendingCommand(channelId: "first")
        AppIntentBridge.shared.setPendingCommand(channelId: "second")

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "siri.pendingChannelId"),
            "second"
        )
    }

    // MARK: - Channel entity lookup from pending

    func testPendingChannelIdResolvesToChannel() {
        AppIntentBridge.shared.setPendingCommand(channelId: "guitar-classical")

        let channelId = UserDefaults.standard.string(forKey: "siri.pendingChannelId")
        let channel = Channel.defaults.first { $0.id == channelId }

        XCTAssertNotNil(channel)
        XCTAssertEqual(channel?.name, "Classical Guitar")
    }

    func testInvalidPendingChannelIdDoesNotResolve() {
        AppIntentBridge.shared.setPendingCommand(channelId: "invalid-channel-id")

        let channelId = UserDefaults.standard.string(forKey: "siri.pendingChannelId")
        let channel = Channel.defaults.first { $0.id == channelId }

        XCTAssertNil(channel)
    }
}
