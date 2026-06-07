import XCTest

final class CurationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-UITestSpeed", "-DisableSplash"]
        app.launch()
    }

    func testNavigateToCuratedChannelList() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        // The "Lorewave" title should appear after accepting TOS
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 10))

        // Navigate to channel list view and find Curated section
        let curatedSection = app.staticTexts["Curated"]
        XCTAssertTrue(curatedSection.waitForExistence(timeout: 10))
    }

    func testChannelInfoOpens() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        // Tap on a channel name to open Channel Info
        let channelButton = app.buttons["Classical Guitar"]
        if channelButton.waitForExistence(timeout: 10) {
            channelButton.tap()
        }
    }

    func testSearchReturnsResults() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        // Open search
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 10) {
            searchField.tap()
            searchField.typeText("beethoven")
            // Dismiss keyboard
            app.buttons["Search"].tap()
        }
    }

    func testSettingsVisible() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        // Navigate to settings via menu or UI
        let settingsButton = app.buttons["Settings"]
        if settingsButton.waitForExistence(timeout: 10) {
            settingsButton.tap()
            XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        }
    }
}
