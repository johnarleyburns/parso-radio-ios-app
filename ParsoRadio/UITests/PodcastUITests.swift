import XCTest

final class PodcastUITests: XCTestCase {
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

    func testPodcastsCategoryVisible() {
        acceptTOSIfNeeded()
        // Find the Podcasts category in the menu
        let podcasts = app.staticTexts["Podcasts"]
        XCTAssertTrue(podcasts.waitForExistence(timeout: 10))
    }

    func testPodcastAddButtonShowsAddSheet() {
        acceptTOSIfNeeded()
        // Tap Podcasts to enter the channel list
        let podcastsButton = app.buttons["Podcasts"]
        if podcastsButton.waitForExistence(timeout: 10) {
            podcastsButton.tap()
        }
        // Verify we see the channel list with built-in channels
        XCTAssertTrue(app.staticTexts["NPR Up First"].waitForExistence(timeout: 10))

        // Tap the "+" add button
        let addButton = app.buttons["Add podcast feed"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        // Verify the PodcastAddView sheet opened
        XCTAssertTrue(app.staticTexts["Add Podcast"].waitForExistence(timeout: 5))
    }

    func testPodcastAddSheetHasURLField() {
        acceptTOSIfNeeded()
        let podcastsButton = app.buttons["Podcasts"]
        if podcastsButton.waitForExistence(timeout: 10) {
            podcastsButton.tap()
        }
        let addButton = app.buttons["Add podcast feed"]
        if addButton.waitForExistence(timeout: 5) {
            addButton.tap()
        }
        // Verify the URL text field exists
        XCTAssertTrue(app.textFields["Podcast Feed URL"].waitForExistence(timeout: 5))
    }

    func testPodcastAddSheetHasSearch() {
        acceptTOSIfNeeded()
        let podcastsButton = app.buttons["Podcasts"]
        if podcastsButton.waitForExistence(timeout: 10) {
            podcastsButton.tap()
        }
        let addButton = app.buttons["Add podcast feed"]
        if addButton.waitForExistence(timeout: 5) {
            addButton.tap()
        }
        // Verify the search field exists
        let searchField = app.textFields["Search iTunes Podcasts…"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
    }

    func testPodcastSheetCancelDismisses() {
        acceptTOSIfNeeded()
        let podcastsButton = app.buttons["Podcasts"]
        if podcastsButton.waitForExistence(timeout: 10) {
            podcastsButton.tap()
        }
        let addButton = app.buttons["Add podcast feed"]
        if addButton.waitForExistence(timeout: 5) {
            addButton.tap()
        }
        // Tap Cancel to dismiss
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 5) {
            cancelButton.tap()
        }
        // Should be back on the channel list
        XCTAssertTrue(app.staticTexts["NPR Up First"].waitForExistence(timeout: 5))
    }

    func testPodcastChannelListHasBuiltInChannels() {
        acceptTOSIfNeeded()
        let podcastsButton = app.buttons["Podcasts"]
        if podcastsButton.waitForExistence(timeout: 10) {
            podcastsButton.tap()
        }
        // All 12 built-in podcast channels should be visible
        let expectedChannels = [
            "NPR Up First", "PBS NewsHour", "Democracy Now!",
            "NPR 1A", "BBC Global News", "DW Inside Europe", "CBC As It Happens",
            "The Joe Rogan Experience", "The Daily", "This American Life",
            "TED Radio Hour", "NPR Politics Podcast"
        ]
        for name in expectedChannels {
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5),
                          "Built-in podcast channel '\(name)' not found")
        }
    }
}
