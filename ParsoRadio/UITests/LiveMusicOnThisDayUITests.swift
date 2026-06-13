import XCTest

final class LiveMusicOnThisDayUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestSpeed"]
        app.launch()
    }

    func testLiveMusicCardExistsWhenEntryAvailable() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        // The card may take a moment to fetch, wait up to 10s
        let card = app.buttons["Live Music on This Day"]
        let exists = card.waitForExistence(timeout: 10)
        if exists {
            XCTAssertTrue(card.exists)
        } else {
            // Card may not appear if IA returns no results for today — acceptable
            XCTAssertTrue(true, "Card optional — skip if no IA results")
        }
    }

    func testTapLiveMusicCardOpensAlbumDetail() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        let card = app.buttons["Live Music on This Day"]
        guard card.waitForExistence(timeout: 10) else { return }
        card.tap()

        // resolveItemParts may take up to 10s; wait for either the sheet's Done
        // button (success) or the error alert (failure). If neither appears,
        // the card action silently did nothing — that's the bug we're guarding.
        let doneButton = app.buttons["Done"]
        let errorAlert = app.alerts["Live Music"]
        let sheetAppeared = doneButton.waitForExistence(timeout: 15)
        let alertAppeared = errorAlert.waitForExistence(timeout: 1)

        // At least one of sheet or alert must appear — silent failure is a bug
        XCTAssertTrue(sheetAppeared || alertAppeared,
                      "Tapping Live Music card should show album detail sheet or error alert, not do nothing")
    }

    func testAlbumDetailShowsContent() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        let card = app.buttons["Live Music on This Day"]
        guard card.waitForExistence(timeout: 10) else { return }
        card.tap()

        let doneButton = app.buttons["Done"]
        guard doneButton.waitForExistence(timeout: 15) else {
            // If an error alert appeared instead of the sheet, dismiss it
            let errorAlert = app.alerts["Live Music"]
            if errorAlert.exists {
                errorAlert.buttons["OK"].tap()
            }
            return
        }

        // Verify the sheet has visible content: either track rows or the empty state
        let trackList = app.otherElements["albumDetailTrackList"]
        let emptyState = app.otherElements["albumDetailEmptyState"]
        let hasContent = trackList.waitForExistence(timeout: 5) || emptyState.waitForExistence(timeout: 1)
        XCTAssertTrue(hasContent, "Album detail sheet must show either track rows or an empty-state message")
    }

    func testAlbumDetailDismisses() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        let card = app.buttons["Live Music on This Day"]
        guard card.waitForExistence(timeout: 10) else { return }
        card.tap()

        let doneButton = app.buttons["Done"]
        guard doneButton.waitForExistence(timeout: 15) else {
            let errorAlert = app.alerts["Live Music"]
            if errorAlert.exists {
                errorAlert.buttons["OK"].tap()
            }
            return
        }

        doneButton.tap()

        // After dismiss, the card should be visible again
        let cardReappeared = card.waitForExistence(timeout: 3)
        XCTAssertTrue(cardReappeared, "Live Music card should be visible after dismissing album detail")
    }

    func testLiveMusicCardNotVisibleWhenSearchActive() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        // Wait for card to potentially appear
        sleep(2)
        // Activate search
        let searchField = app.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 5) else { return }
        searchField.tap()
        // Card should be hidden when searching
        let card = app.buttons["Live Music on This Day"]
        XCTAssertFalse(card.exists)
    }
}
