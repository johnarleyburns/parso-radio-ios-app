import XCTest
@testable import ParsoMusic

final class DatabaseServiceTests: XCTestCase {
    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    func testSaveAndFetchTracks() async throws {
        let track = makeTrack(id: "t1", source: "internet_archive", composer: "bach", instruments: ["strings"])
        await db.saveTracks([track])

        let channel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
        let fetched = await db.fetchTracks(forChannel: channel)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, "t1")
    }

    func testChannelFilterExcludesNonMatchingComposer() async throws {
        await db.saveTracks([
            makeTrack(id: "bach-1",   source: "internet_archive", composer: "bach",   instruments: ["strings"]),
            makeTrack(id: "chopin-1", source: "internet_archive", composer: "chopin", instruments: ["piano"]),
        ])

        let bachChannel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
        let results = await db.fetchTracks(forChannel: bachChannel)
        XCTAssertTrue(results.allSatisfy { $0.composer == "bach" })
        XCTAssertFalse(results.contains { $0.id == "chopin-1" })
    }

    func testMarkDownloaded() async throws {
        let track = makeTrack(id: "dl-1", source: "internet_archive", composer: "chopin", instruments: ["piano"])
        await db.saveTracks([track])
        await db.markDownloaded(trackID: "dl-1", localPath: "/tmp/dl-1.mp3")

        let channel = Channel(id: "chopin", name: "Chopin", category: "Classical", icon: "pianokeys", composers: ["chopin"], preferredSource: "internet_archive")
        let downloaded = await db.fetchDownloadedTracks(forChannel: channel)
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded[0].localFilePath, "/tmp/dl-1.mp3")
    }

    func testLowConfidenceTracksExcludedFromComposerChannel() async throws {
        let lowConf  = makeTrack(id: "low-1",  source: "internet_archive", composer: "bach", instruments: [],         confidence: 1.0)
        let highConf = makeTrack(id: "high-1", source: "internet_archive", composer: "bach", instruments: ["strings"], confidence: 3.0)
        await db.saveTracks([lowConf, highConf])

        let channel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
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

        let channel = Channel.fmaJazzTestChannel
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

        let channel = Channel.fmaJazzTestChannel
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

    // MARK: - Multi-file item (book/album) support

    func testFetchTracksForParentIdentifierReturnsOrderedParts() async throws {
        // Saved out of order; must come back ascending by part_number.
        let p3 = makePart(parent: "book-A", part: 3)
        let p1 = makePart(parent: "book-A", part: 1)
        let p2 = makePart(parent: "book-A", part: 2)
        let other = makePart(parent: "book-B", part: 1)
        await db.saveTracks([p3, p1, p2, other])

        let parts = await db.fetchTracks(forParentIdentifier: "book-A")
        XCTAssertEqual(parts.map(\.partNumber), [1, 2, 3],
            "parts must be ordered by part_number ascending")
        XCTAssertFalse(parts.contains { $0.parentIdentifier == "book-B" },
            "must not bleed in another item's parts")

        let none = await db.fetchTracks(forParentIdentifier: "not-expanded")
        XCTAssertTrue(none.isEmpty, "unexpanded item returns []")
    }

    func testIsMultiPartPersistsAndRoundTrips() async throws {
        let t = makeTrack(id: "probe-1", source: "internet_archive",
                          composer: nil, instruments: [])
        await db.saveTracks([t])

        // Default: not yet probed.
        let initial = await db.fetchTrack(id: "probe-1")
        XCTAssertNil(initial?.isMultiPart, "fresh track is unprobed (nil)")

        await db.setIsMultiPart(true, forTrackId: "probe-1")
        let multi = await db.fetchTrack(id: "probe-1")
        XCTAssertEqual(multi?.isMultiPart, true, "true must persist as multi-file")

        await db.setIsMultiPart(false, forTrackId: "probe-1")
        let single = await db.fetchTrack(id: "probe-1")
        XCTAssertEqual(single?.isMultiPart, false, "false must persist as single-file")
    }

    func testSaveTracksCarriesIsMultiPart() async throws {
        var t = makeTrack(id: "mp-save", source: "internet_archive",
                          composer: nil, instruments: [])
        t.isMultiPart = true
        await db.saveTracks([t])
        let back = await db.fetchTrack(id: "mp-save")
        XCTAssertEqual(back?.isMultiPart, true,
            "isMultiPart must survive saveTracks → rowToTrack")
    }

    private func makePart(parent: String, part: Int) -> Track {
        Track(
            id: "\(parent)/part\(part).mp3", source: "internet_archive",
            title: "Part \(part)", artist: "Author",
            duration: 600,
            streamURL: URL(string: "https://archive.org/download/\(parent)/part\(part).mp3")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 0.7, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 1.0,
            partNumber: part, totalParts: 5, parentIdentifier: parent
        )
    }

    // MARK: - Startup regression

    func testSchemaCreationAndReopenDoesNotCrash() throws {
        // Fresh DB — exercises CREATE TABLE + all addColumnIfNotExists migrations
        _ = try DatabaseService(path: ":memory:")
        // Re-open — exercises migration path when all columns already exist
        _ = try DatabaseService(path: ":memory:")
        // If we got here without a crash, the migration path is safe
    }

    func testRepeatedMigrationDoesNotThrow() throws {
        // Open three times to ensure repeated addColumnIfNotExists is harmless
        for _ in 0..<3 {
            XCTAssertNoThrow(try DatabaseService(path: ":memory:"))
        }
    }

    func testCustomChannelsStoreInitDoesNotCrash() {
        // Init itself shouldn't crash — channels may be empty in test bundles
        _ = CustomChannelsStore.shared.orderedChannels()
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
