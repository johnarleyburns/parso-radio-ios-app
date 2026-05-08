import XCTest
@testable import ParsoRadio

final class ChannelTests: XCTestCase {

    func testDefaultChannelCount() {
        XCTAssertEqual(Channel.defaults.count, 75)
    }

    func testClassicalCategoryHas26Channels() {
        let classicalChannels = Channel.defaults.filter { $0.category == "Classical" }
        XCTAssertEqual(classicalChannels.count, 26,
            "Classical must have 8 period/format + 18 composer channels")
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

    func testFMATagChannelMatchesByTag() {
        let fmaJazz = Channel.defaults.first { $0.id == "fma-jazz" }!
        let jazzTrack  = makeTrack(composer: nil, instruments: [], tags: ["jazz"])
        let rockTrack  = makeTrack(composer: nil, instruments: [], tags: ["rock"])
        let noTagTrack = makeTrack(composer: nil, instruments: [], tags: [])
        XCTAssertTrue(fmaJazz.matches(jazzTrack),  "Jazz track should match FMA Jazz channel")
        XCTAssertFalse(fmaJazz.matches(rockTrack), "Rock track should not match FMA Jazz channel")
        XCTAssertFalse(fmaJazz.matches(noTagTrack),"Untagged track should not match FMA Jazz channel")
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

    // UC7/UC10: all 14 FMA genre channels present under "FMA" category.
    func testFMACategoryHas14Channels() {
        let fmaChannels = Channel.defaults.filter { $0.category == "FMA" }
        XCTAssertEqual(fmaChannels.count, 14, "Expected 14 FMA genre channels")
    }

    func testFMAChannelsHaveValidTags() {
        let fmaChannels = Channel.defaults.filter { $0.category == "FMA" }
        for channel in fmaChannels {
            XCTAssertFalse(channel.tags.isEmpty, "FMA channel \(channel.id) must have at least one tag")
            let hasKnownGenre = channel.tags.first { FMAService.genreMap[$0] != nil } != nil
            XCTAssertTrue(hasKnownGenre, "FMA channel \(channel.id) tags must map to a known FMA genre")
        }
    }

    // UC11: non-Oxford spoken-word channels use "LibriVox Audiobooks" category.
    func testSpokenWordChannelsUseLibriVoxCategory() {
        let librivoxChannels = Channel.defaults.filter {
            $0.contentType == .spokenWord && $0.category != "Oxford Lectures"
        }
        XCTAssertFalse(librivoxChannels.isEmpty, "Expected at least one LibriVox spoken-word channel")
        for channel in librivoxChannels {
            XCTAssertEqual(channel.category, "LibriVox Audiobooks",
                "Spoken-word channel '\(channel.id)' must use 'LibriVox Audiobooks' category")
        }
    }

    // UC13: 22 Oxford Lectures channels, all spoken-word.
    func testOxfordLecturesCategoryHas22Channels() {
        let oxfordChannels = Channel.defaults.filter { $0.category == "Oxford Lectures" }
        XCTAssertEqual(oxfordChannels.count, 22, "Expected 22 Oxford Lectures channels")
    }

    func testOxfordLecturesChannelsAreSpokenWord() {
        let oxfordChannels = Channel.defaults.filter { $0.category == "Oxford Lectures" }
        for channel in oxfordChannels {
            XCTAssertEqual(channel.contentType, .spokenWord,
                "Oxford channel '\(channel.id)' must be contentType .spokenWord")
        }
    }

    func testOxfordLecturesChannelsHaveUnitSlugTag() {
        let oxfordChannels = Channel.defaults.filter { $0.category == "Oxford Lectures" }
        for channel in oxfordChannels {
            XCTAssertFalse(channel.tags.isEmpty,
                "Oxford channel '\(channel.id)' must have a unit slug tag for track matching")
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
