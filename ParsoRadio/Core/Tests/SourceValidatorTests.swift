import XCTest
@testable import ParsoMusic

final class SourceValidatorTests: XCTestCase {

    // A classical composer channel (no feedURL) — broadcast creator tracks must be rejected
    private let bachChannel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")

    // An FMA jazz channel (no feedURL) — non-broadcast creator tracks must pass
    private let jazzChannel = Channel.fmaJazzTestChannel

    func testBroadcastCreatorRejectedForComposerChannel() {
        let broadcastCreators = ["PBS Digital Studios", "BBC Radio 3", "CBC Music", "NPR Music", "Classical Radio WNED"]
        for creator in broadcastCreators {
            let track = makeTrack(rawCreator: creator)
            XCTAssertFalse(
                SourceValidator.isValid(track, for: bachChannel),
                "Track with creator '\(creator)' should be rejected for a composer channel"
            )
        }
    }

    func testNormalCreatorPassesForComposerChannel() {
        let track = makeTrack(rawCreator: "Murray Perahia")
        XCTAssertTrue(SourceValidator.isValid(track, for: bachChannel))
    }

    func testPodcastChannelAlwaysPasses() {
        // Podcast channels have a feedURL set — SourceValidator always returns true for them
        let podcastChannel = Channel.defaults.first { $0.feedURL != nil }
        if let podcastChannel = podcastChannel {
            let broadcastTrack = makeTrack(rawCreator: "NPR")
            XCTAssertTrue(SourceValidator.isValid(broadcastTrack, for: podcastChannel),
                          "Podcast channel (feedURL set) must pass all tracks through SourceValidator")
        }
    }

    func testEmptyCreatorPassesForTagChannel() {
        let track = makeTrack(rawCreator: "")
        XCTAssertTrue(SourceValidator.isValid(track, for: jazzChannel))
    }

    func testCaseInsensitiveKeywordMatch() {
        let track = makeTrack(rawCreator: "Public Broadcasting Service (PBS)")
        XCTAssertFalse(SourceValidator.isValid(track, for: bachChannel))
    }

    // MARK: - Helpers

    private func makeTrack(rawCreator: String) -> Track {
        Track(
            id: UUID().uuidString, source: "internet_archive",
            title: "Test", artist: rawCreator,
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/test")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 0.75,
            rawCreator: rawCreator, composer: nil, instruments: [],
            metadataConfidence: 3.0
        )
    }
}
