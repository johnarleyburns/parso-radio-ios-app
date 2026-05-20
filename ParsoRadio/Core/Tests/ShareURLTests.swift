import XCTest
@testable import ParsoMusic

/// We can't easily reach private helpers in a View, so we re-derive the same
/// share-URL contract from the public Track surface and exercise it here.
final class ShareURLTests: XCTestCase {

    func testIATrackSharesDetailsURL() {
        let t = makeTrack(id: "Stravinsky-Firebird", source: "internet_archive",
                          parentIdentifier: nil)
        let url = ShareURLBuilder.url(for: t)
        XCTAssertEqual(url?.absoluteString,
                       "https://archive.org/details/Stravinsky-Firebird")
    }

    func testIATrackWithSlashIdUsesParent() {
        let t = makeTrack(id: "audiobook_demo/01_intro.mp3",
                          source: "internet_archive",
                          parentIdentifier: "audiobook_demo")
        let url = ShareURLBuilder.url(for: t)
        XCTAssertEqual(url?.absoluteString,
                       "https://archive.org/details/audiobook_demo")
    }

    func testIATrackWithSlashIdButNoParentUsesPrefix() {
        let t = makeTrack(id: "audiobook_demo/01_intro.mp3",
                          source: "internet_archive",
                          parentIdentifier: nil)
        let url = ShareURLBuilder.url(for: t)
        XCTAssertEqual(url?.absoluteString,
                       "https://archive.org/details/audiobook_demo")
    }

    func testNonIATrackFallsBackToStreamURL() {
        let t = makeTrack(id: "fma-1", source: "fma",
                          parentIdentifier: nil,
                          streamURL: URL(string: "https://freemusicarchive.org/x")!)
        let url = ShareURLBuilder.url(for: t)
        XCTAssertEqual(url, t.streamURL)
    }

    func testLocalTrackHasNoShareURL() {
        let t = makeTrack(id: "local-1", source: "local",
                          parentIdentifier: nil,
                          isLocal: true)
        XCTAssertNil(ShareURLBuilder.url(for: t),
                     "Local files should not be shareable (privacy).")
    }

    func testAmbientTrackHasNoShareURL() {
        let t = makeTrack(id: "ambient-1", source: "ambient",
                          parentIdentifier: nil)
        XCTAssertNil(ShareURLBuilder.url(for: t),
                     "Ambient placeholder tracks aren't shareable items.")
    }

    private func makeTrack(id: String,
                           source: String,
                           parentIdentifier: String?,
                           streamURL: URL = URL(string: "https://example.com/audio")!,
                           isLocal: Bool = false) -> Track {
        Track(
            id: id, source: source,
            title: "T", artist: "A",
            duration: 100,
            streamURL: streamURL,
            downloadURL: nil, localFilePath: nil,
            license: .cc0, tags: [],
            qualityScore: 1.0,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0,
            isLocal: isLocal,
            parentIdentifier: parentIdentifier
        )
    }
}
