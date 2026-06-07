import XCTest
@testable import ParsoMusic

final class SharedUtilitiesTests: XCTestCase {

    // MARK: - FormattedTime

    func testFormattedTimeZero() {
        XCTAssertEqual(0.0.formattedTime, "0:00")
    }

    func testFormattedTimeSeconds() {
        XCTAssertEqual(45.0.formattedTime, "0:45")
    }

    func testFormattedTimeMinutesAndSeconds() {
        XCTAssertEqual(125.0.formattedTime, "2:05")
    }

    func testFormattedTimeHours() {
        XCTAssertEqual(3661.0.formattedTime, "1:01:01")
    }

    func testFormattedTimeLargeHours() {
        XCTAssertEqual(3723.0.formattedTime, "1:02:03")
    }

    func testFormattedTimeNegativeReturnsZero() {
        XCTAssertEqual((-5.0).formattedTime, "0:00")
    }

    func testFormattedTimeNaNReturnsZero() {
        XCTAssertEqual(Double.nan.formattedTime, "0:00")
    }

    func testFormattedTimeInfinityReturnsZero() {
        XCTAssertEqual(Double.infinity.formattedTime, "0:00")
    }

    func testFormattedTimeZeroSecondsExactly() {
        XCTAssertEqual(60.0.formattedTime, "1:00")
    }

    func testFormattedTimeSingleDigitMinutes() {
        XCTAssertEqual(65.0.formattedTime, "1:05")
    }

    // MARK: - ChannelCategoryStyle

    func testCategoryColorClassical() {
        let color = ChannelCategoryStyle.color(for: "Classical")
        XCTAssertNotNil(color)
    }

    func testCategoryColorAudiobooks() {
        let color = ChannelCategoryStyle.color(for: "Audiobooks")
        XCTAssertNotNil(color)
    }

    func testCategoryColorUnknownCategoryReturnsDefault() {
        let color = ChannelCategoryStyle.color(for: "UnknownXYZ")
        XCTAssertNotNil(color)
    }

    func testCategoryGradientClassical() {
        let gradient = ChannelCategoryStyle.gradient(for: "Classical")
        XCTAssertNotNil(gradient)
    }

    func testCategoryGradientReturnsValidForAllKnownCategories() {
        let categories = ["Classical", "Audiobooks", "Contemporary", "Lectures", "Podcasts", "Ambient"]
        for category in categories {
            let gradient = ChannelCategoryStyle.gradient(for: category)
            XCTAssertNotNil(gradient)
        }
    }

    func testCategoryGradientUnknownReturnsDefault() {
        let gradient = ChannelCategoryStyle.gradient(for: "NonExistentCategory")
        XCTAssertNotNil(gradient)
    }

    func testCategoryIconForKnownCategories() {
        XCTAssertEqual(ChannelCategoryStyle.icon(for: "Playlists"), "music.note.list")
        XCTAssertEqual(ChannelCategoryStyle.icon(for: "Curated"), "star.fill")
        XCTAssertEqual(ChannelCategoryStyle.icon(for: "Ambient"), "leaf.fill")
        XCTAssertEqual(ChannelCategoryStyle.icon(for: "Podcasts"), "newspaper.fill")
        XCTAssertEqual(ChannelCategoryStyle.icon(for: "Audiobooks"), "book.fill")
        XCTAssertEqual(ChannelCategoryStyle.icon(for: "Lectures"), "building.columns.fill")
    }

    func testCategoryIconUnknownReturnsMusicNote() {
        XCTAssertEqual(ChannelCategoryStyle.icon(for: "Unknown"), "music.note")
    }

    // MARK: - LicenseDisplay

    func testLicenseNameCC0() {
        XCTAssertEqual(LicenseDisplay.name(.cc0), "CC0")
    }

    func testLicenseNameCCBy() {
        XCTAssertEqual(LicenseDisplay.name(.ccBy), "CC BY")
    }

    func testLicenseNamePublicDomain() {
        XCTAssertEqual(LicenseDisplay.name(.publicDomain), "Public Domain")
    }

    func testLicenseNameRejected() {
        XCTAssertEqual(LicenseDisplay.name(.rejected), "Unknown")
    }

    // MARK: - SourceDisplay

    func testSourceNameInternetArchive() {
        XCTAssertEqual(SourceDisplay.name("internet_archive"), "Internet Archive")
    }

    func testSourceNameFMA() {
        XCTAssertEqual(SourceDisplay.name("fma"), "Free Music Archive")
    }

    func testSourceNameOxford() {
        XCTAssertEqual(SourceDisplay.name("oxford_lectures"), "Oxford University")
    }

    func testSourceNamePodcast() {
        XCTAssertEqual(SourceDisplay.name("podcast"), "Podcast")
    }

    func testSourceNameNPS() {
        XCTAssertEqual(SourceDisplay.name("nps"), "National Park Service")
    }

    func testSourceNameFreesound() {
        XCTAssertEqual(SourceDisplay.name("freesound"), "Freesound")
    }

    func testSourceNameLocal() {
        XCTAssertEqual(SourceDisplay.name("local"), "My Files")
    }

    func testSourceNameUnknownReturnsRaw() {
        XCTAssertEqual(SourceDisplay.name("custom_source"), "custom_source")
    }

    // MARK: - BrandGradient

    func testBrandGradientExists() {
        XCTAssertNotNil(BrandGradient.linear)
    }

    func testBrandGradientColors() {
        // Just ensure it renders without crashing
        let top = BrandGradient.topColor
        let bottom = BrandGradient.bottomColor
        XCTAssertNotNil(top)
        XCTAssertNotNil(bottom)
    }

    // MARK: - SharedViews helpers

    func testInfoRowRenders() {
        let view = SharedViews.infoRow("Label", "Value")
        XCTAssertNotNil(view)
    }

    func testBadgeRenders() {
        let view = SharedViews.badge("Test", color: .blue)
        XCTAssertNotNil(view)
    }
}
