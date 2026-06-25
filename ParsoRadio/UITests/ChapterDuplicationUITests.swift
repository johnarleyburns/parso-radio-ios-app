import XCTest

/// Issue #2: an audiobook's chapters must each appear exactly once — not three
/// times (the multi-bitrate triple bug). Seeded with 5 chapters × 3 MP3
/// variants; the chapter list must show 5 rows.
final class ChapterDuplicationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestSeed"]
        app.launch()
    }

    func testChaptersAreNotDuplicated() {
        let bookCard = app.buttons["jumpbackin.card.book.gallipoli_ia"]
        XCTAssertTrue(bookCard.waitForExistence(timeout: 40))
        XCTAssertTrue(bookCard.tapUntil(app.buttons["player.dismiss"]),
            "tapping the book must open the now-playing sheet")

        let chaptersButton = app.buttons["Chapters"]
        XCTAssertTrue(chaptersButton.waitForExistence(timeout: 15),
            "the audiobook surface must offer a Chapters button")

        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'chapterlist.row.'"))
        XCTAssertTrue(chaptersButton.tapUntil(rows.element(boundBy: 0)),
            "the chapter list must populate")

        XCTAssertEqual(rows.count, 5,
            "5 unique chapters must show, not 15 bitrate-variant duplicates")
    }
}
