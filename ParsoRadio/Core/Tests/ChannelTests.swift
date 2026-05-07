import XCTest
@testable import ParsoRadio

final class ChannelTests: XCTestCase {

    func testDefaultChannelCount() {
        XCTAssertEqual(Channel.defaults.count, 34)
    }

    func testBachVivaldiChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.composers, ["bach", "vivaldi"])
        XCTAssertEqual(ch?.instruments, ["strings"])
    }

    func testChopinRachmaninoffChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "chopin-rachmaninoff-piano" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.composers, ["chopin", "rachmaninoff"])
        XCTAssertEqual(ch?.instruments, ["piano"])
    }

    func testChannelMatchesComposerAndInstrument() {
        let channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        let matching = makeTrack(composer: "bach", instruments: ["strings"])
        let wrongComposer = makeTrack(composer: "chopin", instruments: ["strings"])
        let wrongInstrument = makeTrack(composer: "bach", instruments: ["piano"])
        let noComposer = makeTrack(composer: nil, instruments: ["strings"])

        XCTAssertTrue(channel.matches(matching))
        XCTAssertFalse(channel.matches(wrongComposer))
        XCTAssertFalse(channel.matches(wrongInstrument))
        XCTAssertFalse(channel.matches(noComposer))
    }

    func testTagChannelMatchesByTag() {
        let classical = Channel.defaults.first { $0.id == "classical" }!
        let classicalTrack = makeTrack(composer: "bach", instruments: [], tags: ["classical"])
        let rockTrack     = makeTrack(composer: nil,   instruments: [], tags: ["rock"])
        let noTagTrack    = makeTrack(composer: nil,   instruments: [], tags: [])
        XCTAssertTrue(classical.matches(classicalTrack), "Classical track should match classical channel")
        XCTAssertFalse(classical.matches(rockTrack),    "Rock track should not match classical channel")
        XCTAssertFalse(classical.matches(noTagTrack),   "Untagged track should not match classical channel")
    }

    func testJazzPianoChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "jazz-piano" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.category, "Jazz & Blues")
        XCTAssertEqual(ch?.instruments, ["piano"])
        XCTAssertEqual(ch?.tags, ["jazz"])
    }

    func testJazzPianoMatchesOnlyPianoJazz() {
        let ch = Channel.defaults.first { $0.id == "jazz-piano" }!
        let pianoJazz = makeTrack(composer: nil, instruments: ["piano"], tags: ["jazz"])
        let violinJazz = makeTrack(composer: nil, instruments: ["violin"], tags: ["jazz"])
        XCTAssertTrue(ch.matches(pianoJazz), "Piano jazz track should match Jazz Piano channel")
        XCTAssertFalse(ch.matches(violinJazz), "Violin jazz track should not match Jazz Piano channel")
    }

    func testSoulRnbChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "soul-rnb" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.category, "Pop & World")
        XCTAssertTrue(ch?.tags.contains("soul") == true)
        XCTAssertTrue(ch?.tags.contains("r&b") == true)
    }

    func testOldTimeRootsChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "old-time-roots" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.category, "Rock & Country")
        XCTAssertTrue(ch?.tags.contains("old-time") == true)
        XCTAssertTrue(ch?.tags.contains("folk") == true)
    }

    func testTagChannelDoesNotMatchWrongGenre() {
        let country = Channel.defaults.first { $0.id == "country" }!
        let rachTrack = makeTrack(composer: "rachmaninoff", instruments: ["piano"], tags: ["classical"])
        XCTAssertFalse(country.matches(rachTrack), "Rachmaninoff track must not appear in Country channel")
    }

    func testSoftCafeTagsUpdated() {
        let ch = Channel.defaults.first { $0.id == "soft-cafe" }!
        XCTAssertTrue(ch.tags.contains("jazz"),        "Soft Café must have jazz tag")
        XCTAssertTrue(ch.tags.contains("bossa nova"),  "Soft Café must have bossa nova tag")
        XCTAssertFalse(ch.tags.contains("lo-fi"),      "Soft Café must not have lo-fi tag")
        XCTAssertFalse(ch.tags.contains("acoustic"),   "Soft Café must not have acoustic tag")
    }

    func testStudyFocusTagsUpdated() {
        let ch = Channel.defaults.first { $0.id == "study-focus" }!
        XCTAssertTrue(ch.tags.contains("instrumental"), "Study Focus must have instrumental tag")
        XCTAssertTrue(ch.tags.contains("ambient"),      "Study Focus must have ambient tag")
        XCTAssertFalse(ch.tags.contains("lo-fi"),       "Study Focus must not have lo-fi tag")
    }

    func testSoftCafeMatchesByUpdatedTags() {
        let ch = Channel.defaults.first { $0.id == "soft-cafe" }!
        let jazzTrack = makeTrack(composer: nil, instruments: [], tags: ["jazz"])
        let lofiTrack = makeTrack(composer: nil, instruments: [], tags: ["lo-fi"])
        XCTAssertTrue(ch.matches(jazzTrack),  "Jazz track should match Soft Café after tag fix")
        XCTAssertFalse(ch.matches(lofiTrack), "Lo-fi track should NOT match Soft Café after tag fix")
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
