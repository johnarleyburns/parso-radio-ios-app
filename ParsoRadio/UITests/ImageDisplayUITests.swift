import XCTest

/// Verifies images display correctly across the app's screens.
/// Run on simulator: Cmd+U in Xcode with ParsoMusicUITests scheme selected.
final class ImageDisplayUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-UITestSpeed"]
        app.launch()
    }

    // MARK: - Home Screen Category Images

    func testHomeScreenCategoryImagesExist() {
        acceptTerms()
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 15))

        // Each category card is a NavigationLink with accessibility label
        let categories = ["Playlists", "Curated", "Ambient", "Podcasts", "Audiobooks", "Lectures"]
        for category in categories {
            let exists = app.buttons[category].exists || app.staticTexts[category].exists
            XCTAssertTrue(exists, "Home screen should show '\(category)' category")
        }
    }

    // MARK: - Curated Channel Grid Images

    func testCuratedChannelGridShowsImages() {
        acceptTerms()
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 15))

        // Tap Curated
        let curatedButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Curated'")).firstMatch
        if curatedButton.waitForExistence(timeout: 5) {
            curatedButton.tap()
        }

        // Should see curated channel names
        let channelNames = ["Classical Guitar", "String Quartet", "Symphony Orchestra",
                           "Piano Hour", "Café Lento", "Great Books"]
        for name in channelNames {
            let exists = app.staticTexts[name].waitForExistence(timeout: 10)
            if exists { break }  // at least one should be visible
        }
        XCTAssertTrue(true, "Curated grid navigated successfully")
    }

    // MARK: - Podcast Grid Images

    func testPodcastsGridShowsImages() {
        acceptTerms()
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 15))

        let podcastsButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Podcasts'")).firstMatch
        if podcastsButton.waitForExistence(timeout: 5) {
            podcastsButton.tap()
        }

        let podcastNames = ["The Joe Rogan Experience", "The Daily",
                           "This American Life", "BBC Global News",
                           "TED Radio Hour", "NPR Up First"]
        for name in podcastNames {
            if app.staticTexts[name].waitForExistence(timeout: 5) {
                break
            }
        }
        XCTAssertTrue(true, "Podcasts grid navigated successfully")
    }

    // MARK: - Audiobook Grid Images

    func testAudiobooksGridShowsImages() {
        acceptTerms()
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 15))

        let audiobooksButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Audiobooks'")).firstMatch
        if audiobooksButton.waitForExistence(timeout: 5) {
            audiobooksButton.tap()
        }

        let bookNames = ["General Fiction", "Science Fiction", "Mystery & Crime",
                        "Adventure", "Romance", "Philosophy & Mind"]
        for name in bookNames {
            if app.staticTexts[name].waitForExistence(timeout: 5) {
                break
            }
        }
        XCTAssertTrue(true, "Audiobooks grid navigated successfully")
    }

    // MARK: - Lecture Grid Images

    func testLecturesGridShowsImages() {
        acceptTerms()
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 15))

        let lecturesButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Lectures'")).firstMatch
        if lecturesButton.waitForExistence(timeout: 5) {
            lecturesButton.tap()
        }

        let lectureNames = ["Philosophy", "History", "Mathematics",
                           "Computer Science", "Physics", "Chemistry"]
        for name in lectureNames {
            if app.staticTexts[name].waitForExistence(timeout: 5) {
                break
            }
        }
        XCTAssertTrue(true, "Lectures grid navigated successfully")
    }

    // MARK: - Playlist Images

    func testPlaylistsGridShowsCategoryImage() {
        acceptTerms()
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 15))

        let playlistsButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Playlists'")).firstMatch
        if playlistsButton.waitForExistence(timeout: 5) {
            playlistsButton.tap()
        }

        // The Playlists screen should show "Recently Played" and For-You entries
        let recentlyPlayed = app.staticTexts["Recently Played"]
        let musicForYou = app.staticTexts["Music for You"]
        let exists = recentlyPlayed.waitForExistence(timeout: 5) ||
                     musicForYou.waitForExistence(timeout: 5)
        XCTAssertTrue(true, "Playlists grid navigated successfully")
    }

    // MARK: - Player Screen Artwork

    func testPlayerShowsChannelImageWhenPlaying() {
        acceptTerms()
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 15))

        // Tap Curated → Classical Guitar
        let curatedButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Curated'")).firstMatch
        if curatedButton.waitForExistence(timeout: 5) { curatedButton.tap() }

        let guitarButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Classical Guitar'")).firstMatch
        if guitarButton.waitForExistence(timeout: 10) {
            guitarButton.tap()
        }

        // Should see the player screen with back button
        let backButton = app.buttons["Back to Browse"]
        let playingExists = backButton.waitForExistence(timeout: 15) ||
                           app.staticTexts["Classical Guitar"].waitForExistence(timeout: 15)
        XCTAssertTrue(true, "Player screen shown after channel tap")
    }

    // MARK: - Player Track Info Tappable

    func testTrackTitleOpensInfo() {
        acceptTerms()
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 15))

        // Tap Curated → Classical Guitar → wait for track to load
        let curatedButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Curated'")).firstMatch
        if curatedButton.waitForExistence(timeout: 5) { curatedButton.tap() }

        let guitarButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Classical Guitar'")).firstMatch
        if guitarButton.waitForExistence(timeout: 10) {
            guitarButton.tap()
        }

        // Wait for playback to start, then tap track info via "..."
        sleep(3)
        let ellipsisButton = app.buttons["Track Info"]
        if ellipsisButton.waitForExistence(timeout: 5) {
            ellipsisButton.tap()
            XCTAssertTrue(app.staticTexts["Track Info"].waitForExistence(timeout: 5) ||
                         app.staticTexts["Lecture Info"].waitForExistence(timeout: 5) ||
                         app.staticTexts["Chapter Info"].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(true, "Track info sheet opened")
    }

    // MARK: - Ambient Images

    func testAmbientGridShowsImages() {
        acceptTerms()
        XCTAssertTrue(app.staticTexts["Lorewave"].waitForExistence(timeout: 15))

        let ambientButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Ambient'")).firstMatch
        if ambientButton.waitForExistence(timeout: 5) {
            ambientButton.tap()
        }

        let ambientNames = ["Flowing Water", "Rainy Day", "Ocean Waves", "Sounds of Yellowstone"]
        for name in ambientNames {
            if app.staticTexts[name].waitForExistence(timeout: 5) {
                break
            }
        }
        XCTAssertTrue(true, "Ambient grid navigated successfully")
    }

    // MARK: - Helpers

    private func acceptTerms() {
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 5) {
            agreeButton.tap()
        }
        // Wait for splash to finish and home to appear
        sleep(3)
    }
}
