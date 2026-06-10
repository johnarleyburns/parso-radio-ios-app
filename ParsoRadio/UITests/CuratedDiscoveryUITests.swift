import XCTest

final class CuratedDiscoveryUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-UITestSpeed"]
        app.launch()
    }

    func acceptGatesIfPresent() {
        let ageButton = app.buttons["I'm 16 or older"]
        if ageButton.waitForExistence(timeout: 3) { ageButton.tap() }
        let agreeButton = app.buttons["I Agree"]
        if agreeButton.waitForExistence(timeout: 3) { agreeButton.tap() }
    }

    func testCuratedDiscoveryCardAppears() {
        acceptGatesIfPresent()
        sleep(3) // Let home screen load

        // Print all buttons visible
        let allButtons = app.buttons.allElementsBoundByIndex.map { $0.label }
        print("ALL BUTTONS: \(allButtons)")

        // Try to find Curated Music
        let curatedButton = app.buttons.allElementsBoundByIndex.first {
            $0.label.contains("Curated")
        }
        if let btn = curatedButton {
            print("Found button: \(btn.label)")
            btn.tap()
        } else {
            // Try scrolling
            let scrollView = app.scrollViews.firstMatch
            scrollView.swipeUp()
            sleep(1)
            scrollView.swipeUp()
            sleep(1)
            let btn2 = app.buttons.allElementsBoundByIndex.first { $0.label.contains("Curated") }
            if let b2 = btn2 {
                print("Found after scroll: \(b2.label)")
                b2.tap()
            } else {
                print("STILL NOT FOUND after scroll")
                XCTFail("Curated Music button not found")
                return
            }
        }

        sleep(5) // Wait for Curated Discovery to load

        // Print what's on screen
        let labels = app.staticTexts.allElementsBoundByIndex.map { $0.label }
        print("SCREEN LABELS: \(labels)")

        let discoveryCard = app.staticTexts["Curated Discovery"]
        if discoveryCard.waitForExistence(timeout: 10) {
            XCTAssertTrue(discoveryCard.exists)
        } else {
            // Print full hierarchy
            print("FULL TREE:")
            print(app.debugDescription)
            XCTFail("Curated Discovery card not found")
        }
    }
}
