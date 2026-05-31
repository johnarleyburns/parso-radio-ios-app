import XCTest
@testable import ParsoMusic

@MainActor
final class CuratorControllerTests: XCTestCase {

    func test_freshControllerStartsLocked() {
        let c = CuratorController()
        XCTAssertFalse(c.isUnlocked, "every cold launch starts locked")
    }

    func test_unlockRequiresCorrectHardcodedPin() {
        let c = CuratorController()
        XCTAssertFalse(c.unlock(pin: "0000"))
        XCTAssertFalse(c.unlock(pin: "1234"))
        XCTAssertFalse(c.unlock(pin: "999999"))
        XCTAssertFalse(c.isUnlocked)
        XCTAssertTrue(c.unlock(pin: "128800"))
        XCTAssertTrue(c.isUnlocked)
    }

    func test_unlockToleratesNonDigitNoise() {
        let c = CuratorController()
        XCTAssertTrue(c.unlock(pin: "12-88-00"),
            "non-digit chars are stripped — the 6 digits must still match")
        c.lock()
        XCTAssertTrue(c.unlock(pin: " 128800 "),
            "whitespace ignored")
        c.lock()
        XCTAssertFalse(c.unlock(pin: "12880"),
            "missing a digit must NOT unlock (digits must equal exactly)")
    }

    func test_lockReverts() {
        let c = CuratorController()
        _ = c.unlock(pin: "128800")
        XCTAssertTrue(c.isUnlocked)
        c.lock()
        XCTAssertFalse(c.isUnlocked)
    }

    func test_curatedChannelsAreOnlyCuratedCategoryAndRegistryBacked() {
        let channels = CuratorController.curatedChannels()
        XCTAssertFalse(channels.isEmpty)
        for ch in channels {
            XCTAssertEqual(ch.category, "Curated",
                "curator must ONLY surface Curated-category channels (not News, Audiobooks, For You, Lectures, Ambient)")
            XCTAssertNotNil(ch.iaQueryEntry,
                "curated channels must be registry-backed")
        }
    }

    func test_curatedChannelsExcludesAudiobookCategory() {
        let channels = CuratorController.curatedChannels()
        // LibriVox audiobook channels like Fantasy & Mythology, Mystery & Crime
        // live in the "Audiobooks" category — they must NOT show up here.
        XCTAssertFalse(channels.contains { $0.category == "Audiobooks" })
    }

    func test_curatedChannelsExcludesForYouAndOthers() {
        let channels = CuratorController.curatedChannels()
        let ids = Set(channels.map(\.id))
        XCTAssertFalse(ids.contains("music-for-you"))
        XCTAssertFalse(ids.contains("books-for-you"))
    }
}
