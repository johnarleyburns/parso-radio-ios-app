import XCTest
@testable import ParsoRadio

final class ChannelTests: XCTestCase {

    func testDefaultChannelCount() {
        XCTAssertEqual(Channel.defaults.count, 23)
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

    func testTagChannelDoesNotMatchWrongGenre() {
        let country = Channel.defaults.first { $0.id == "country" }!
        let rachTrack = makeTrack(composer: "rachmaninoff", instruments: ["piano"], tags: ["classical"])
        XCTAssertFalse(country.matches(rachTrack), "Rachmaninoff track must not appear in Country channel")
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
