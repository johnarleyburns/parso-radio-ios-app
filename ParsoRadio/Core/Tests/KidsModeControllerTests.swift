import XCTest
@testable import ParsoMusic

@MainActor
final class KidsModeControllerTests: XCTestCase {
    // Each controller gets its own ephemeral defaults so tests never touch the
    // shared store or leave the app stuck in Kids Mode.
    private func makeController() -> KidsModeController {
        let suite = "KidsModeTests-\(UUID().uuidString)"
        return KidsModeController(defaults: UserDefaults(suiteName: suite)!)
    }

    func test_enableSetsFlagAndPin() {
        let c = makeController()
        XCTAssertFalse(c.isEnabled)
        c.enable(pin: "1234")
        XCTAssertTrue(c.isEnabled)
        XCTAssertTrue(c.verify(pin: "1234"))
        XCTAssertFalse(c.verify(pin: "9999"))
    }

    func test_disableRequiresCorrectPin() {
        let c = makeController()
        c.enable(pin: "1234")
        XCTAssertFalse(c.disable(pin: "0000"), "wrong PIN must not disable")
        XCTAssertTrue(c.isEnabled)
        XCTAssertTrue(c.disable(pin: "1234"))
        XCTAssertFalse(c.isEnabled)
    }

    func test_enableRejectsShortPin() {
        let c = makeController()
        c.enable(pin: "12")
        XCTAssertFalse(c.isEnabled, "a non-4-digit PIN must not enable Kids Mode")
    }

    func test_allowedChannelsAreExactlyTheTwoChildrensChannels() {
        let ids = Set(KidsModeController.allowedChannels().map(\.id))
        XCTAssertEqual(ids, ["childrens-songs", "childrens-books"],
            "Kids Mode must expose exactly the two children's channels (and they must exist)")
    }

    func test_normalizeKeepsDigitsAndCapsAtFour() {
        XCTAssertEqual(KidsModeController.normalize("12ab345"), "1234")
        XCTAssertEqual(KidsModeController.normalize("9"), "9")
    }
}
