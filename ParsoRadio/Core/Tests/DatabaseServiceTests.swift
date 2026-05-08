import XCTest
@testable import ParsoRadio

final class DatabaseServiceTests: XCTestCase {
    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    func testSaveAndFetchTracks() async throws {
        let track = makeTrack(id: "t1", composer: "bach", instruments: ["strings"])
        await db.saveTracks([track])

        let channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        let fetched = await db.fetchTracks(forChannel: channel)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, "t1")
    }

    func testChannelFilterExcludesNonMatchingComposer() async throws {
        await db.saveTracks([
            makeTrack(id: "bach-1",   composer: "bach",   instruments: ["strings"]),
            makeTrack(id: "chopin-1", composer: "chopin", instruments: ["piano"]),
        ])

        let bachChannel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        let results = await db.fetchTracks(forChannel: bachChannel)
        XCTAssertTrue(results.allSatisfy { $0.composer == "bach" || $0.composer == "vivaldi" })
        XCTAssertFalse(results.contains { $0.id == "chopin-1" })
    }

    func testMarkDownloaded() async throws {
        let track = makeTrack(id: "dl-1", composer: "chopin", instruments: ["piano"])
        await db.saveTracks([track])
        await db.markDownloaded(trackID: "dl-1", localPath: "/tmp/dl-1.mp3")

        let channel = Channel.defaults.first { $0.id == "chopin-rachmaninoff-piano" }!
        let downloaded = await db.fetchDownloadedTracks(forChannel: channel)
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded[0].localFilePath, "/tmp/dl-1.mp3")
    }

    func testLowConfidenceTracksExcludedFromComposerChannel() async throws {
        let lowConf  = makeTrack(id: "low-1",  composer: "bach", instruments: [],         confidence: 1.0)
        let highConf = makeTrack(id: "high-1", composer: "bach", instruments: ["strings"], confidence: 3.0)
        await db.saveTracks([lowConf, highConf])

        let channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        let results = await db.fetchTracks(forChannel: channel)
        XCTAssertFalse(results.contains { $0.id == "low-1" })
        XCTAssertTrue(results.contains  { $0.id == "high-1" })
    }

    // Tag-only channels use confidence threshold 0.0 — low-confidence tracks must be returned.
    // This verifies the fix for "No tracks available" on FMA/tag channels.
    func testLowConfidenceTracksIncludedInTagChannel() async throws {
        let lowConf = Track(
            id: "jazz-low", source: "fma",
            title: "Low Confidence Jazz", artist: "Unknown",
            duration: 180,
            streamURL: URL(string: "https://freemusicarchive.org/track/jazz-low/stream/")!,
            downloadURL: nil, localFilePath: nil,
            license: .cc0, tags: ["jazz"],
            qualityScore: 0.3 / 4.0,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 0.3
        )
        await db.saveTracks([lowConf])

        let channel = Channel.defaults.first { $0.id == "jazz-bar" }!
        let results = await db.fetchTracks(forChannel: channel)
        XCTAssertTrue(
            results.contains { $0.id == "jazz-low" },
            "Tag-only channel must include low-confidence FMA tracks (confidence=0.3 was previously filtered)"
        )
    }

    func testTrackCount() async throws {
        await db.saveTracks([
            makeTrack(id: "c1", composer: "bach",   instruments: ["strings"]),
            makeTrack(id: "c2", composer: "chopin", instruments: ["piano"]),
        ])
        let count = await db.trackCount()
        XCTAssertEqual(count, 2)
    }

    func testReplaceOnConflict() async throws {
        let original = makeTrack(id: "dup", composer: "bach",    instruments: ["strings"])
        let updated  = makeTrack(id: "dup", composer: "vivaldi", instruments: ["strings"])
        await db.saveTracks([original])
        await db.saveTracks([updated])

        let count = await db.trackCount()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Helpers

    private func makeTrack(id: String, composer: String?, instruments: [String], confidence: Double = 3.0) -> Track {
        Track(
            id: id, source: "internet_archive",
            title: "Test", artist: "Artist",
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: confidence / 4.0,
            rawCreator: composer ?? "",
            composer: composer,
            instruments: instruments,
            metadataConfidence: confidence
        )
    }
}
