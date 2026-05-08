import XCTest
@testable import ParsoRadio

final class DatabaseServiceTests: XCTestCase {
    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    func testSaveAndFetchTracks() async throws {
        let track = makeTrack(id: "t1", source: "internet_archive", composer: "bach", instruments: ["strings"])
        await db.saveTracks([track])

        let channel = Channel.defaults.first { $0.id == "bach" }!
        let fetched = await db.fetchTracks(forChannel: channel)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, "t1")
    }

    func testChannelFilterExcludesNonMatchingComposer() async throws {
        await db.saveTracks([
            makeTrack(id: "bach-1",   source: "internet_archive", composer: "bach",   instruments: ["strings"]),
            makeTrack(id: "chopin-1", source: "internet_archive", composer: "chopin", instruments: ["piano"]),
        ])

        let bachChannel = Channel.defaults.first { $0.id == "bach" }!
        let results = await db.fetchTracks(forChannel: bachChannel)
        XCTAssertTrue(results.allSatisfy { $0.composer == "bach" })
        XCTAssertFalse(results.contains { $0.id == "chopin-1" })
    }

    func testMarkDownloaded() async throws {
        let track = makeTrack(id: "dl-1", source: "internet_archive", composer: "chopin", instruments: ["piano"])
        await db.saveTracks([track])
        await db.markDownloaded(trackID: "dl-1", localPath: "/tmp/dl-1.mp3")

        let channel = Channel.defaults.first { $0.id == "chopin" }!
        let downloaded = await db.fetchDownloadedTracks(forChannel: channel)
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded[0].localFilePath, "/tmp/dl-1.mp3")
    }

    func testLowConfidenceTracksExcludedFromComposerChannel() async throws {
        let lowConf  = makeTrack(id: "low-1",  source: "internet_archive", composer: "bach", instruments: [],         confidence: 1.0)
        let highConf = makeTrack(id: "high-1", source: "internet_archive", composer: "bach", instruments: ["strings"], confidence: 3.0)
        await db.saveTracks([lowConf, highConf])

        let channel = Channel.defaults.first { $0.id == "bach" }!
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

        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let results = await db.fetchTracks(forChannel: channel)
        XCTAssertTrue(
            results.contains { $0.id == "jazz-low" },
            "Tag-only channel must include low-confidence FMA tracks (confidence=0.3 was previously filtered)"
        )
    }

    // UC18: fetchTracks must filter to channel.preferredSource when set.
    func testFetchTracksFiltersToPreferredSource() async throws {
        let fmaTrack = Track(
            id: "fma-jazz-1", source: "fma",
            title: "Jazz Track", artist: "Artist A",
            duration: 180,
            streamURL: URL(string: "https://freemusicarchive.org/track/1/stream/")!,
            downloadURL: nil, localFilePath: nil,
            license: .cc0, tags: ["jazz"],
            qualityScore: 0.6,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0
        )
        let iaTrack = Track(
            id: "ia-jazz-1", source: "internet_archive",
            title: "Jazz Track IA", artist: "Artist B",
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/ia-jazz-1")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: ["jazz"],
            qualityScore: 0.6,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0
        )
        await db.saveTracks([fmaTrack, iaTrack])

        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        XCTAssertEqual(channel.preferredSource, "fma")
        let results = await db.fetchTracks(forChannel: channel)
        XCTAssertTrue(results.contains  { $0.id == "fma-jazz-1" }, "FMA track must be returned for fma-jazz channel")
        XCTAssertFalse(results.contains { $0.id == "ia-jazz-1"  }, "IA track must be excluded for fma channel")
    }

    func testTrackCount() async throws {
        await db.saveTracks([
            makeTrack(id: "c1", source: "internet_archive", composer: "bach",   instruments: ["strings"]),
            makeTrack(id: "c2", source: "internet_archive", composer: "chopin", instruments: ["piano"]),
        ])
        let count = await db.trackCount()
        XCTAssertEqual(count, 2)
    }

    func testReplaceOnConflict() async throws {
        let original = makeTrack(id: "dup", source: "internet_archive", composer: "bach",    instruments: ["strings"])
        let updated  = makeTrack(id: "dup", source: "internet_archive", composer: "vivaldi", instruments: ["strings"])
        await db.saveTracks([original])
        await db.saveTracks([updated])

        let count = await db.trackCount()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Helpers

    private func makeTrack(id: String, source: String, composer: String?, instruments: [String], confidence: Double = 3.0) -> Track {
        Track(
            id: id, source: source,
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
