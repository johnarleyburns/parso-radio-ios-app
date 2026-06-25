import XCTest
@testable import ParsoMusic

@MainActor
final class MadeForYouShelfStoreTests: XCTestCase {

    private var db: DatabaseService!
    private var tasteStore: TasteProfileStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        tasteStore = TasteProfileStore(db: db)
        UserDefaults.standard.removeObject(forKey: "tasteProfileBackfillVersion")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "tasteProfileBackfillVersion")
        db = nil
        tasteStore = nil
        super.tearDown()
    }

    func testEmptyProfileStartsIdle() async {
        let hasProfile = await tasteStore.hasAnyProfile()
        XCTAssertFalse(hasProfile, "No profile should exist for fresh install")
        let shelfStore = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore)
        XCTAssertEqual(shelfStore.state, .idle, "Initial state should be idle")
    }

    func testExistingPlayHistoryBackfillCreatesProfileTerms() async {
        await db.saveTracks([
            Track.makeStub(id: "track1", title: "Test Track")
        ])
        await db.recordPlayed(channelId: "test-channel", trackId: "track1")

        let playedTracks = await db.fetchRecentlyPlayedTracksForTasteBackfill(limit: 200)
        XCTAssertFalse(playedTracks.isEmpty, "Should find recently played tracks")

        let hasProfileBefore = await tasteStore.hasAnyProfile()
        XCTAssertFalse(hasProfileBefore, "Should have no profile before backfill")

        let shelfStore = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore)
        await shelfStore.ensureTasteBackfillIfNeeded()
        let hasProfileAfter = await tasteStore.hasAnyProfile()

        XCTAssertTrue(hasProfileAfter, "Backfill should have created profile terms from play history")
    }

    func testDailyCacheStoresAndRetrievesOrderedTrackIds() async {
        await db.saveTracks([
            Track.makeStub(id: "track_a", title: "A"),
            Track.makeStub(id: "track_b", title: "B"),
            Track.makeStub(id: "track_c", title: "C"),
        ])
        let shelfStore = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore)
        await shelfStore.saveDailyCache(trackIds: ["track_a", "track_b", "track_c"], source: "personalized")

        let cached = await shelfStore.loadDailyCache()
        if let cached {
            XCTAssertEqual(cached.count, 3)
            XCTAssertEqual(cached[0], "track_a")
            XCTAssertEqual(cached[2], "track_c")
        }
    }

    func testMigrationV2MovesAudiobookTermsToSpokenAndPreservesOnboarding() async {
        let audiobookChannel = Channel.defaults.first { $0.category == "Audiobooks" }!
        let book = Track(
            id: "book-1", source: "internet_archive", title: "Pride and Prejudice",
            artist: "Jane Austen", duration: 0,
            streamURL: URL(string: "https://example.com/book-1.mp3")!,
            downloadURL: nil, localFilePath: nil, license: .publicDomain,
            tags: ["fiction"], qualityScore: 3.0, rawCreator: "Jane Austen",
            composer: nil, instruments: [], metadataConfidence: 1.0)
        await db.saveTracks([book])
        await db.recordPlayed(channelId: audiobookChannel.id, trackId: book.id)

        // Simulate the v1 state: audiobook author polluted the MUSIC bucket,
        // plus a genuine onboarding music term that has no play-history row.
        await tasteStore.upsertTerm(bucket: "music", axis: "creator", term: "jane austen", increment: 1.0)
        await tasteStore.upsertTerm(bucket: "music", axis: "creator", term: "bach", increment: 1.75)

        let store = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore)
        await store.migrateTasteProfileV2()

        let music = await tasteStore.fetchProfile(bucket: "music")
        let spoken = await tasteStore.fetchProfile(bucket: "spoken")

        XCTAssertTrue(spoken.creatorTerms.contains { $0.term == "jane austen" },
                       "audiobook author must move to the spoken bucket after v2 migration")
        XCTAssertFalse(music.creatorTerms.contains { $0.term == "jane austen" },
                        "audiobook author must be purged from the music bucket")
        XCTAssertTrue(music.creatorTerms.contains { $0.term == "bach" },
                       "onboarding music term must be preserved in the music bucket")
    }

    func testMigrationHarvestsBookListenHistoryIntoSpoken() async {
        await db.recordBookListened(workKey: "twain-huck", identifier: "huck-finn",
                                    title: "Huckleberry Finn", author: "Mark Twain",
                                    subjects: "fiction,humor")

        let store = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore)
        await store.migrateTasteProfileV2()

        let spoken = await tasteStore.fetchProfile(bucket: "spoken")
        XCTAssertTrue(spoken.creatorTerms.contains { $0.term == "mark twain" },
                       "book-listen author must seed the spoken bucket even with no channel play")
        XCTAssertTrue(spoken.subjectTerms.contains { $0.term == "fiction" },
                       "book-listen subjects must seed the spoken bucket")
    }

    func testClearTasteProfileTermsEmptiesOnlyTasteTerms() async {
        await tasteStore.upsertTerm(bucket: "music", axis: "creator", term: "bach", increment: 2.0)
        await db.saveTracks([Track.makeStub(id: "t1", title: "T1")])
        await db.recordPlayed(channelId: "c1", trackId: "t1")

        await db.clearTasteProfileTerms()

        let hasProfile = await tasteStore.hasAnyProfile()
        XCTAssertFalse(hasProfile, "clearTasteProfileTerms must empty the taste terms table")
        let recents = await db.fetchRecentlyPlayedWithChannel(limit: 10)
        XCTAssertEqual(recents.count, 1, "play history must be left intact")
    }

    func testDailyCacheHandlesNewDay() async {
        let shelfStore = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore)
        await shelfStore.saveDailyCache(trackIds: ["track_a"], source: "cold_start")
        let cached = await shelfStore.loadDailyCache()
        if let cached {
            XCTAssertEqual(cached.count, 1)
        }
    }
}
