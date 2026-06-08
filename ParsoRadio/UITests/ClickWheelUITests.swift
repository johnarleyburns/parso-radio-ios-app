import XCTest

/// Click test: exercises the main player screen's interactive elements to
/// detect crashes. Runs on the Now Playing screen after TOS acceptance.
final class ClickWheelUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-UITestSpeed", "-DisableSplash"]
        app.launch()
    }

    private func acceptTOSIfNeeded() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
    }

    /// Tap every button on the Now Playing screen and verify no crash.
    func testClickWheelAllButtonsNoCrash() {
        acceptTOSIfNeeded()

        // Wait for the player screen to be fully loaded (splash gone, iPodView visible).
        // The Play/Pause button is always present on the ClickWheel.
        XCTAssertTrue(app.images["playpause.fill"].waitForExistence(timeout: 10))

        // Tap Play/Pause — toggles playback (safe even if nothing loaded).
        app.images["playpause.fill"].tap()
        sleep(1)

        // Tap Forward — skip button.
        app.images["forward.fill"].tap()
        sleep(1)

        // Tap Back — previous track button.
        app.images["backward.fill"].tap()
        sleep(1)

        // Tap Menu (top of click wheel) — opens MainMenuView.
        // The menu region is identified by the "line.3.horizontal" SF Symbol.
        let menuIcon = app.images["line.3.horizontal"]
        if menuIcon.exists {
            // Tap near the top of the wheel where the menu icon sits.
            menuIcon.tap()
            sleep(1)

            // Dismiss the menu if it opened.
            let doneButton = app.buttons["Done"]
            if doneButton.waitForExistence(timeout: 3) {
                doneButton.tap()
                sleep(1)
            } else {
                // Try alternative dismiss: tap outside sheet.
                app.swipeDown(velocity: .fast)
                sleep(1)
            }
        }

        // Tap More Options — Track Info (center button on the click wheel).
        // The center of the wheel opens a "More Options" sheet when a track
        // is loaded. This may be empty if nothing is playing, but the tap
        // should not crash regardless.
        // We target the center well region by tapping the center of the screen.
        let centerPoint = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        centerPoint.tap()
        sleep(1)

        // Verify the app is still alive (didn't crash)
        XCTAssertTrue(app.exists, "App should still be running after all button taps")
    }
}
