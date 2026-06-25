import XCTest

/// Issue #1: a book/album found in search must be favoritable from its detail
/// sheet (previously there was no favorite affordance anywhere but the player).
/// Exercised offline by opening the album detail sheet via the player's
/// "Album tracks" button.
final class FavoritesInSearchUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestSeed"]
        app.launch()
    }

    func testItemDetailSheetHasWorkingFavoriteButton() {
        let musicCard = app.buttons["jumpbackin.card.track.album_ia/track_01.mp3"]
        XCTAssertTrue(musicCard.waitForExistence(timeout: 40))
        XCTAssertTrue(musicCard.tapUntil(app.buttons["player.dismiss"]),
            "tapping the track must open the now-playing sheet")

        let albumButton = app.buttons["Album tracks"]
        XCTAssertTrue(albumButton.waitForExistence(timeout: 25),
            "the music surface must expose the Album tracks button for a multi-part item")
        XCTAssertTrue(albumButton.tapUntil(app.buttons["itemdetail.favorite"]),
            "the book/album detail sheet must offer an Add to Favorites button")

        let favButton = app.buttons["itemdetail.favorite"]
        XCTAssertEqual(favButton.label, "Add to favorites",
            "the item starts unfavorited")

        favButton.forceTap()
        // The toggle is async (DB write + reload); wait for the label to flip.
        let removed = NSPredicate(format: "label == %@", "Remove from favorites")
        expectation(for: removed, evaluatedWith: favButton)
        waitForExpectations(timeout: 8) { error in
            XCTAssertNil(error,
                "tapping the favorite button must toggle the item into favorites")
        }
    }
}
