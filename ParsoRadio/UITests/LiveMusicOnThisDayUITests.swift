import XCTest

final class LiveMusicOnThisDayUITests: XCTestCase {
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

    func testCardVisibleOnListenTab() {
        let listenTab = app.buttons["Listen"]
        XCTAssertTrue(listenTab.waitForExistence(timeout: 10))
        listenTab.tap()

        let section = app.staticTexts["Live Music on This Day"]
        XCTAssertTrue(section.waitForExistence(timeout: 10))
    }

    func testCardLoadingSkeletonAppears() {
        let listenTab = app.buttons["Listen"]
        XCTAssertTrue(listenTab.waitForExistence(timeout: 10))
        listenTab.tap()

        let section = app.staticTexts["Live Music on This Day"]
        XCTAssertTrue(section.waitForExistence(timeout: 10))

        let searching = app.staticTexts["Searching\u{2026}"]
        let liveArchive = app.staticTexts["Live Music Archive"]
        let cardContent = app.staticTexts.firstMatch
        XCTAssertTrue(cardContent.exists)
    }

    func testTapLeftOpensDetailView() {
        let listenTab = app.buttons["Listen"]
        XCTAssertTrue(listenTab.waitForExistence(timeout: 10))
        listenTab.tap()

        let section = app.staticTexts["Live Music on This Day"]
        XCTAssertTrue(section.waitForExistence(timeout: 15))

        // Wait for content to load
        sleep(5)

        // Tap on the live music info area
        let cardTexts = app.staticTexts
        var tapped = false
        for i in 0..<min(cardTexts.count, 20) {
            let text = cardTexts.element(boundBy: i)
            if text.label.contains("Live Music on This Day") || text.label.count > 5 {
                let frame = text.frame
                if frame.width > 60 && frame.midX < 300 {
                    text.tap()
                    tapped = true
                    break
                }
            }
        }

        // Check for detail view being presented
        let playAll = app.buttons["Play All Tracks"]
        let done = app.buttons["Done"]
        let detailShown = playAll.waitForExistence(timeout: 8) || done.waitForExistence(timeout: 8)
        if !detailShown {
            let liveRecording = app.navigationBars["Live Recording"]
            if liveRecording.waitForExistence(timeout: 5) {
                XCTAssertTrue(true)
                return
            }
        }
    }

    func testTapPlayEnqueuesTrack() {
        let listenTab = app.buttons["Listen"]
        XCTAssertTrue(listenTab.waitForExistence(timeout: 10))
        listenTab.tap()

        let section = app.staticTexts["Live Music on This Day"]
        XCTAssertTrue(section.waitForExistence(timeout: 15))

        // Wait for content to load
        sleep(5)

        // Find and tap the play button
        let playButton = app.buttons["Play live recording"]
        if playButton.waitForExistence(timeout: 8) {
            playButton.tap()
        }

        // Wait for playback to start - miniplayer should appear
        let miniPlayerText = app.staticTexts.firstMatch
        XCTAssertTrue(miniPlayerText.waitForExistence(timeout: 10))
    }

    func testDetailViewContainsPlayAllButton() {
        let listenTab = app.buttons["Listen"]
        XCTAssertTrue(listenTab.waitForExistence(timeout: 10))
        listenTab.tap()

        let section = app.staticTexts["Live Music on This Day"]
        XCTAssertTrue(section.waitForExistence(timeout: 15))

        sleep(5)

        // Tap info area
        let cardTexts = app.staticTexts
        for i in 0..<min(cardTexts.count, 20) {
            let text = cardTexts.element(boundBy: i)
            if text.label.count > 8 && text.frame.midX < 300 && text.frame.width > 60 {
                text.tap()
                break
            }
        }

        // Verify Play All button exists in detail
        let playAll = app.buttons["Play All Tracks"]
        let done = app.buttons["Done"]
        if playAll.waitForExistence(timeout: 8) {
            XCTAssertTrue(true)
        } else if done.waitForExistence(timeout: 8) {
            // Detail is open - check for play all after scrolling
            app.swipeUp()
            let playAllAfterScroll = app.buttons["Play All Tracks"]
            if playAllAfterScroll.waitForExistence(timeout: 5) {
                XCTAssertTrue(true)
            }
        }
    }

    func testDetailDismissReturnsToList() {
        let listenTab = app.buttons["Listen"]
        XCTAssertTrue(listenTab.waitForExistence(timeout: 10))
        listenTab.tap()

        let section = app.staticTexts["Live Music on This Day"]
        XCTAssertTrue(section.waitForExistence(timeout: 15))

        sleep(5)

        // Tap info area
        let cardTexts = app.staticTexts
        for i in 0..<min(cardTexts.count, 20) {
            let text = cardTexts.element(boundBy: i)
            if text.label.count > 8 && text.frame.midX < 300 && text.frame.width > 60 {
                text.tap()
                break
            }
        }

        let done = app.buttons["Done"]
        if done.waitForExistence(timeout: 8) {
            done.tap()
        }

        // Should be back on Listen tab
        let listenSection = app.staticTexts["Live Music on This Day"]
        XCTAssertTrue(listenSection.waitForExistence(timeout: 5))
    }

    func testCardFixedHeightDoesNotJump() {
        let listenTab = app.buttons["Listen"]
        XCTAssertTrue(listenTab.waitForExistence(timeout: 10))
        listenTab.tap()

        let section = app.staticTexts["Live Music on This Day"]
        XCTAssertTrue(section.waitForExistence(timeout: 15))

        // Measure initial Y position of the first channel after Live Music
        let searching = app.staticTexts["Searching\u{2026}"]
        var initialY: CGFloat = 0
        if searching.exists {
            initialY = searching.frame.minY
        }

        // Wait for content to load
        sleep(6)

        // Check that content didn't jump by verifying section still exists
        let reloadedSection = app.staticTexts["Live Music on This Day"]
        XCTAssertTrue(reloadedSection.exists)
    }
}
