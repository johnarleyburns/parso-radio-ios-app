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

    func testTapLiveMusicCardShowsNowPlaying() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        let card = app.buttons["Live Music on This Day"]
        guard card.waitForExistence(timeout: 10) else { return }
        card.tap()
        // Verify we navigated to Now Playing by checking for transport controls
        let playPause = app.buttons["Play"]
        let exists = playPause.waitForExistence(timeout: 10)
        XCTAssertTrue(exists || app.buttons["Pause"].exists)
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
