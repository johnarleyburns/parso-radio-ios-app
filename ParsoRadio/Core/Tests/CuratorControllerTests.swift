import XCTest
@testable import ParsoMusic

@MainActor
final class CuratorControllerTests: XCTestCase {
    private func makeController() -> CuratorController {
        let suite = "CuratorTests-\(UUID().uuidString)"
        return CuratorController(defaults: UserDefaults(suiteName: suite)!)
    }

    func test_freshControllerHasNoPinAndIsLocked() {
        let c = makeController()
        XCTAssertFalse(c.hasPin)
        XCTAssertFalse(c.isUnlocked)
    }

    func test_setPinPersistsButDoesNotUnlock() {
        let c = makeController()
        c.setPin("1234")
        XCTAssertTrue(c.hasPin)
        XCTAssertFalse(c.isUnlocked,
            "setting the PIN must NOT auto-unlock — that's a separate step")
    }

    func test_unlockRequiresCorrectPin() {
        let c = makeController()
        c.setPin("1234")
        XCTAssertFalse(c.unlock(pin: "9999"))
        XCTAssertFalse(c.isUnlocked)
        XCTAssertTrue(c.unlock(pin: "1234"))
        XCTAssertTrue(c.isUnlocked)
    }

    func test_lockReverts() {
        let c = makeController()
        c.setPin("4321")
        _ = c.unlock(pin: "4321")
        c.lock()
        XCTAssertFalse(c.isUnlocked)
    }

    func test_setPinRejectsShortPin() {
        let c = makeController()
        c.setPin("12")
        XCTAssertFalse(c.hasPin, "a sub-4-digit PIN must be rejected")
    }

    func test_curatedChannelsAreRegistryBacked() {
        let channels = CuratorController.curatedChannels()
        XCTAssertFalse(channels.isEmpty)
        for ch in channels {
            XCTAssertNotNil(ch.iaQueryEntry,
                "curated channels must be registry-backed (have an iaQuery)")
        }
    }
}
