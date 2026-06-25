import XCTest

/// Issue #3 / #4: "Jump back in" must show one card for the whole book (not a
/// chapter), and tapping it must resume the book on the AUDIOBOOK surface.
/// Seeded deterministically via the `-uiTestSeed` launch argument.
final class JumpBackInBookUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestSeed"]
        app.launch()
    }

    private var bookCard: XCUIElement { app.buttons["jumpbackin.card.book.gallipoli_ia"] }
    private var musicCard: XCUIElement { app.buttons["jumpbackin.card.track.album_ia/track_01.mp3"] }

    func testJumpBackInShowsCollapsedBookWorkCard() {
        XCTAssertTrue(bookCard.waitForExistence(timeout: 40),
            "the book must appear as ONE collapsed work card")
        XCTAssertTrue(app.staticTexts["Gallipoli"].exists,
            "the card shows the book title")
        XCTAssertFalse(app.staticTexts["Chapter 1"].exists,
            "the book must not surface its individual chapters as cards")
    }

    func testMusicStaysOnePerTrack() {
        XCTAssertTrue(musicCard.waitForExistence(timeout: 40),
            "a music track must remain a per-track card, not collapse")
    }

    func testTappingBookResumesOnAudiobookSurface() {
        XCTAssertTrue(bookCard.waitForExistence(timeout: 40))
        XCTAssertTrue(bookCard.tapUntil(app.buttons["player.dismiss"]),
            "tapping the book must open the now-playing sheet")
        // The audiobook surface (SpokenControls) shows a Chapters button and no
        // Album-tracks button — the music surface shows the opposite.
        XCTAssertTrue(app.buttons["Chapters"].waitForExistence(timeout: 15),
            "a resumed book must render the audiobook surface (Chapters control)")
        XCTAssertFalse(app.buttons["Album tracks"].exists,
            "a book must never render the music surface")
        XCTAssertFalse(app.buttons["Album tracks unavailable"].exists)
    }

    func testTappingMusicOpensMusicSurface() {
        XCTAssertTrue(musicCard.waitForExistence(timeout: 40))
        XCTAssertTrue(musicCard.tapUntil(app.buttons["player.dismiss"]),
            "tapping a track must open the now-playing sheet")
        // The music surface never shows the spoken Chapters control.
        XCTAssertFalse(app.buttons["Chapters"].waitForExistence(timeout: 5),
            "a music track must not render the audiobook surface")
    }
}

extension XCUIElement {
    /// Taps the element, falling back to a center-coordinate tap when XCUITest
    /// reports the element as not hittable. SwiftUI custom `Button`s nested in a
    /// horizontal `ScrollView` inside a `List` are frequently flagged
    /// non-hittable even though they are visible and tappable.
    func forceTap() {
        if isHittable {
            tap()
        } else {
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// Taps repeatedly until `target` appears, tolerating taps that are dropped
    /// while a cold-launched app is still settling. Returns whether `target`
    /// became visible.
    @discardableResult
    func tapUntil(_ target: XCUIElement, attempts: Int = 4, timeout: TimeInterval = 12) -> Bool {
        for _ in 0..<attempts {
            forceTap()
            if target.waitForExistence(timeout: timeout) { return true }
        }
        return false
    }
}
