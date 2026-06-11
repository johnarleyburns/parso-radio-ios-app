import XCTest

/// Regression: when auditioning a track in the curator, @EnvironmentObject on
/// ChannelInfoView (and CuratedChannelsGrid) caused body recomputation when
/// PlayerViewModel.currentChannel changed to nil. That recompute cascade
/// destabilized .sheet(item:) and .sheet(isPresented:) presentations, causing
/// the curator to jump channels and lose verdicts.
///
/// Fix: playerVM is now a plain `let` in both ChannelInfoView and
/// CuratedChannelsGrid — no observation, no recompute cascade.
final class CuratorChannelStabilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-UITestSpeed", "-DisableSplash"]
        app.launch()
    }

    /// Open curator for Classical Guitar channel and verify the title
    /// remains correct after network operations (Load More Candidates).
    /// This used to fail because @EnvironmentObject recompute cascades
    /// destabilized the sheet presentation.
    func test_curatorSheetTitleRemainsStableAfterLoadingCandidates() {
        acceptAgeGate()

        // On fresh launch, HomeView shows channel cards. "Classical Guitar"
        // is a shipped default that always appears in the Curated section.
        let channelCard = app.buttons["Classical Guitar"]
        XCTAssertTrue(channelCard.waitForExistence(timeout: 15),
                      "Classical Guitar channel card must exist")

        // Tap to play the channel, then open Channel Info to reach Curate.
        channelCard.tap()
        sleep(2)

        // The player appears. Tap the channel name / info button to open
        // ChannelInfoView where "Curate this Channel" lives.
        // Look for a navigation bar with the channel name or a "Track Info" button.
        let trackInfoButton = app.buttons["Track Info"]
        if trackInfoButton.waitForExistence(timeout: 5) {
            trackInfoButton.tap()
        }
        sleep(1)

        // In ChannelInfoView, tap "Curate this Channel"
        let curateButton = app.buttons["Curate this Channel"]
        if curateButton.waitForExistence(timeout: 5) {
            curateButton.tap()
        } else {
            // Fallback: dismiss player and use the context menu on HomeView
            dismissPlayerIfVisible()
            channelCard.press(forDuration: 0.8)
            if app.buttons["Curate"].waitForExistence(timeout: 3) {
                app.buttons["Curate"].tap()
            } else {
                XCTFail("Could not find Curate action for Classical Guitar")
                return
            }
        }

        // THE KEY ASSERTION: curator sheet must show the correct channel
        let navTitle = app.navigationBars["Classical Guitar"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 8),
                      "Curator must open for Classical Guitar")

        // Trigger network / DB ops that used to cause the sheet to jump
        let loadButton = app.buttons["Load More Candidates"]
        if loadButton.waitForExistence(timeout: 5) {
            loadButton.tap()
            sleep(5) // wait for network fetch
        }

        // Title must STILL be Classical Guitar (not jumped to another channel)
        XCTAssertTrue(app.navigationBars["Classical Guitar"].exists,
                      "Curator title must remain Classical Guitar after operations")

        // Dismiss
        dismissCuratorIfVisible()
    }

    // MARK: - Helpers

    private func acceptAgeGate() {
        let agree = app.buttons["I Agree"]
        if agree.waitForExistence(timeout: 6) { agree.tap() }
        // May also need to dismiss the "Lorewave" splash
        sleep(1)
    }

    private func dismissPlayerIfVisible() {
        // If full-screen player is showing, swipe down to dismiss
        let doneButton = app.buttons["Done"]
        if doneButton.exists { doneButton.tap(); return }
        // Swipe down on player
        let playerView = app.otherElements["PlayerView"]
        if playerView.exists {
            playerView.swipeDown()
            sleep(1)
        }
    }

    private func dismissCuratorIfVisible() {
        let done = app.buttons["Done"]
        if done.exists { done.tap() }
    }
}
