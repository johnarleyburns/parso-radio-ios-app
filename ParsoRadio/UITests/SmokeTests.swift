import XCTest

final class SmokeTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestSpeed"]
        app.launch()
    }

    func testAppLaunches() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    func testAcceptTermsAndBrowseChannels() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 10))
    }

    func testNavigateToSearch() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 10) {
            searchField.tap()
            searchField.typeText("beethoven")
            app.keyboards.buttons["Search"].tap()
            XCTAssertTrue(app.staticTexts["Results"].waitForExistence(timeout: 15))
        }
    }
}
