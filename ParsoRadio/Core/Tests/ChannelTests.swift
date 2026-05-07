import XCTest
@testable import ParsoRadio

final class ChannelTests: XCTestCase {

    func testDefaultChannelCount() {
        XCTAssertEqual(Channel.defaults.count, 11)
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

    func testGenreChannelMatchesAnyComposer() {
        let classical = Channel.defaults.first { $0.id == "classical" }!
        let anyComposer = makeTrack(composer: "bach", instruments: [])
        let noComposer = makeTrack(composer: nil, instruments: [])
        XCTAssertTrue(classical.matches(anyComposer))
        XCTAssertTrue(classical.matches(noComposer))
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

    private func makeTrack(composer: String?, instruments: [String]) -> Track {
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
            tags: [],
            qualityScore: 1.0,
            rawCreator: composer ?? "",
            composer: composer,
            instruments: instruments,
            metadataConfidence: 3.0
        )
    }
}
