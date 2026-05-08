import XCTest
@testable import ParsoRadio

final class ChannelTests: XCTestCase {

    func testDefaultChannelCount() {
        // 28 Classical + 22 Audiobooks + 14 Contemporary + 22 Lectures + 10 News = 96
        XCTAssertEqual(Channel.defaults.count, 96)
    }

    func testClassicalCategoryHas28Channels() {
        let classicalChannels = Channel.defaults.filter { $0.category == "Classical" }
        XCTAssertEqual(classicalChannels.count, 28,
            "Classical must have 10 period/format/instrument + 18 composer channels")
    }

    func testBachChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "bach" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.composers, ["bach"])
        XCTAssertEqual(ch?.category, "Classical")
        XCTAssertEqual(ch?.preferredSource, "internet_archive")
    }

    func testMozartChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "mozart" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.composers, ["mozart"])
        XCTAssertEqual(ch?.category, "Classical")
    }

    func testClassicalGuitarChannelExists() {
        let ch = Channel.defaults.first { $0.id == "classical-guitar" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.category, "Classical")
        XCTAssertTrue(ch?.tags.contains("classical guitar") == true)
    }

    func testCelloChannelExists() {
        let ch = Channel.defaults.first { $0.id == "cello" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.category, "Classical")
        XCTAssertTrue(ch?.tags.contains("cello") == true)
    }

    func testFMATagChannelMatchesByTag() {
        let fmaJazz = Channel.defaults.first { $0.id == "fma-jazz" }!
        let jazzTrack  = makeTrack(composer: nil, instruments: [], tags: ["jazz"])
        let rockTrack  = makeTrack(composer: nil, instruments: [], tags: ["rock"])
        let noTagTrack = makeTrack(composer: nil, instruments: [], tags: [])
        XCTAssertTrue(fmaJazz.matches(jazzTrack),  "Jazz track should match Jazz channel")
        XCTAssertFalse(fmaJazz.matches(rockTrack), "Rock track should not match Jazz channel")
        XCTAssertFalse(fmaJazz.matches(noTagTrack),"Untagged track should not match Jazz channel")
    }

    func testPreferredSourceAssignedCorrectly() {
        let bach         = Channel.defaults.first { $0.id == "bach" }!
        let fmaJazz      = Channel.defaults.first { $0.id == "fma-jazz" }!
        let greekPhilo   = Channel.defaults.first { $0.id == "greek-philosophy" }!
        let oxford       = Channel.defaults.first { $0.id == "oxford-philosophy" }!

        XCTAssertEqual(bach.preferredSource,       "internet_archive")
        XCTAssertEqual(fmaJazz.preferredSource,    "fma")
        XCTAssertEqual(greekPhilo.preferredSource, "internet_archive")
        XCTAssertEqual(oxford.preferredSource,     "oxford_lectures")
    }

    // Contemporary category (formerly FMA): 14 genre channels.
    func testContemporaryCategoryHas14Channels() {
        let channels = Channel.defaults.filter { $0.category == "Contemporary" }
        XCTAssertEqual(channels.count, 14, "Expected 14 Contemporary genre channels")
    }

    func testContemporaryChannelsHaveValidTags() {
        let channels = Channel.defaults.filter { $0.category == "Contemporary" }
        for channel in channels {
            XCTAssertFalse(channel.tags.isEmpty, "Contemporary channel \(channel.id) must have at least one tag")
            let hasKnownGenre = channel.tags.first { FMAService.genreMap[$0] != nil } != nil
            XCTAssertTrue(hasKnownGenre, "Contemporary channel \(channel.id) tags must map to a known FMA genre")
        }
    }

    func testAudiobooksCategoryHas22Channels() {
        let lvChannels = Channel.defaults.filter { $0.category == "Audiobooks" }
        XCTAssertEqual(lvChannels.count, 22,
            "Expected 4 named + 18 genre Audiobooks channels")
    }

    // Non-feed spoken-word channels (not Lectures or News) must use "Audiobooks" category.
    func testNonFeedSpokenWordChannelsUseAudiobooksCategory() {
        let librivoxChannels = Channel.defaults.filter {
            $0.contentType == .spokenWord
                && $0.category != "Lectures"
                && $0.category != "News"
        }
        XCTAssertFalse(librivoxChannels.isEmpty, "Expected at least one Audiobooks spoken-word channel")
        for channel in librivoxChannels {
            XCTAssertEqual(channel.category, "Audiobooks",
                "Spoken-word channel '\(channel.id)' must use 'Audiobooks' category")
        }
    }

    // Lectures category (formerly Oxford Lectures): 22 channels, all spoken-word.
    func testLecturesCategoryHas22Channels() {
        let channels = Channel.defaults.filter { $0.category == "Lectures" }
        XCTAssertEqual(channels.count, 22, "Expected 22 Lectures channels")
    }

    func testLecturesChannelsAreSpokenWord() {
        let channels = Channel.defaults.filter { $0.category == "Lectures" }
        for channel in channels {
            XCTAssertEqual(channel.contentType, .spokenWord,
                "Lectures channel '\(channel.id)' must be contentType .spokenWord")
        }
    }

    func testLecturesChannelsHaveUnitSlugTag() {
        let channels = Channel.defaults.filter { $0.category == "Lectures" }
        for channel in channels {
            XCTAssertFalse(channel.tags.isEmpty,
                "Lectures channel '\(channel.id)' must have a unit slug tag for track matching")
        }
    }

    // News category: 10 channels with feedURL.
    func testNewsCategoryHas10Channels() {
        let newsChannels = Channel.defaults.filter { $0.category == "News" }
        XCTAssertEqual(newsChannels.count, 10, "Expected 10 News channels")
    }

    func testNewsChannelsHaveFeedURL() {
        let newsChannels = Channel.defaults.filter { $0.category == "News" }
        for channel in newsChannels {
            XCTAssertNotNil(channel.feedURL, "News channel '\(channel.id)' must have a feedURL")
            XCTAssertFalse(channel.feedURL?.isEmpty == true, "News channel '\(channel.id)' feedURL must not be empty")
        }
    }

    func testNewsChannelsAreSpokenWord() {
        let newsChannels = Channel.defaults.filter { $0.category == "News" }
        for channel in newsChannels {
            XCTAssertEqual(channel.contentType, .spokenWord,
                "News channel '\(channel.id)' must be contentType .spokenWord")
        }
    }

    func testChannelCodableRoundtrip() throws {
        let original = Channel.defaults[0]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.composers, original.composers)
        XCTAssertEqual(decoded.instruments, original.instruments)
    }

    // MARK: - Helpers

    private func makeTrack(composer: String?, instruments: [String], tags: [String] = []) -> Track {
        Track(
            id: UUID().uuidString,
            source: "internet_archive",
            title: "Test Track",
            artist: "Test Artist",
            duration: 180,
            streamURL: URL(string: "https://example.com/track.mp3")!,
            downloadURL: nil,
            localFilePath: nil,
            license: .publicDomain,
            tags: tags,
            qualityScore: 1.0,
            rawCreator: composer ?? "",
            composer: composer,
            instruments: instruments,
            metadataConfidence: 3.0
        )
    }
}
