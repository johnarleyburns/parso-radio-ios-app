import XCTest

final class JumpBackInUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestSpeed"]
        app.launch()

        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
    }

    func testJumpBackInHiddenWithoutHistory() throws {
        let header = app.staticTexts["Jump Back In"]
        XCTAssertFalse(header.exists,
            "Jump Back In should not appear when there is no listening history")
    }
}
