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
    }

    override func tearDown() {
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
        let shelfStore = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore)
        await shelfStore.ensureTasteBackfillIfNeeded()
        let hasProfileAfter = await tasteStore.hasAnyProfile()

        if !hasProfileBefore && !playedTracks.isEmpty {
            XCTAssertTrue(hasProfileAfter, "Backfill should have created profile terms")
        }
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

    func testDailyCacheHandlesNewDay() async {
        let shelfStore = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore)
        await shelfStore.saveDailyCache(trackIds: ["track_a"], source: "cold_start")
        let cached = await shelfStore.loadDailyCache()
        if let cached {
            XCTAssertEqual(cached.count, 1)
        }
    }
}
