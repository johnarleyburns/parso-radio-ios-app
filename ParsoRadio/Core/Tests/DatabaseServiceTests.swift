import XCTest
@testable import ParsoRadio

final class DatabaseServiceTests: XCTestCase {
    private var db: DatabaseService!

    override func setUp() throws {
        super.setUp()
        db = try DatabaseService(path: ":memory:")
    }

    func testSaveAndFetchTracks() throws {
        let track = makeTrack(id: "t1", composer: "bach", instruments: ["strings"])
        db.saveTracks([track])
        // Allow serial queue to flush
        Thread.sleep(forTimeInterval: 0.05)

        let channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        let fetched = db.fetchTracks(forChannel: channel)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, "t1")
    }

    func testChannelFilterExcludesNonMatchingComposer() throws {
        db.saveTracks([
            makeTrack(id: "bach-1",   composer: "bach",   instruments: ["strings"]),
            makeTrack(id: "chopin-1", composer: "chopin", instruments: ["piano"]),
        ])
        Thread.sleep(forTimeInterval: 0.05)

        let bachChannel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        let results = db.fetchTracks(forChannel: bachChannel)
        XCTAssertTrue(results.allSatisfy { $0.composer == "bach" || $0.composer == "vivaldi" })
        XCTAssertFalse(results.contains { $0.id == "chopin-1" })
    }

    func testMarkDownloaded() throws {
        let track = makeTrack(id: "dl-1", composer: "chopin", instruments: ["piano"])
        db.saveTracks([track])
        Thread.sleep(forTimeInterval: 0.05)

        db.markDownloaded(trackID: "dl-1", localPath: "/tmp/dl-1.mp3")
        Thread.sleep(forTimeInterval: 0.05)

        let channel = Channel.defaults.first { $0.id == "chopin-rachmaninoff-piano" }!
        let downloaded = db.fetchDownloadedTracks(forChannel: channel)
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded[0].localFilePath, "/tmp/dl-1.mp3")
    }

    func testLowConfidenceTracksExcludedFromComposerChannel() throws {
        let lowConf = makeTrack(id: "low-1", composer: "bach", instruments: [], confidence: 1.0)
        let highConf = makeTrack(id: "high-1", composer: "bach", instruments: ["strings"], confidence: 3.0)
        db.saveTracks([lowConf, highConf])
        Thread.sleep(forTimeInterval: 0.05)

        let channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        let results = db.fetchTracks(forChannel: channel)
        XCTAssertFalse(results.contains { $0.id == "low-1" })
        XCTAssertTrue(results.contains { $0.id == "high-1" })
    }

    func testTrackCount() throws {
        db.saveTracks([
            makeTrack(id: "c1", composer: "bach",   instruments: ["strings"]),
            makeTrack(id: "c2", composer: "chopin", instruments: ["piano"]),
        ])
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(db.trackCount(), 2)
    }

    func testReplaceOnConflict() throws {
        let original = makeTrack(id: "dup", composer: "bach", instruments: ["strings"])
        let updated  = makeTrack(id: "dup", composer: "vivaldi", instruments: ["strings"])
        db.saveTracks([original])
        Thread.sleep(forTimeInterval: 0.05)
        db.saveTracks([updated])
        Thread.sleep(forTimeInterval: 0.05)

        XCTAssertEqual(db.trackCount(), 1)
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
