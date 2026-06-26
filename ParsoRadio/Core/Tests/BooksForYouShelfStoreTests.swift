import XCTest
@testable import ParsoMusic

@MainActor
final class BooksForYouShelfStoreTests: XCTestCase {

    private var db: DatabaseService!
    private var tasteStore: TasteProfileStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        tasteStore = TasteProfileStore(db: db)
        UserDefaults.standard.removeObject(forKey: "tasteProfileBackfillVersion")
        clearShelfSnapshots()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "tasteProfileBackfillVersion")
        clearShelfSnapshots()
        db = nil
        tasteStore = nil
        super.tearDown()
    }

    private func clearShelfSnapshots() {
        for key in ["madeForYou.snapshot.music", "madeForYou.snapshot.music.kind",
                    "madeForYou.snapshot.books", "madeForYou.snapshot.books.kind"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func testBooksShelfStartsIdle() async {
        let store = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore, shelf: .books)
        XCTAssertEqual(store.state, .idle)
    }

    func testBooksAndMusicDailyCachesAreNamespacedSeparately() async {
        let music = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore, shelf: .music)
        let books = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore, shelf: .books)

        await music.saveDailyCache(trackIds: ["m1", "m2", "m3"], source: "personalized")
        await books.saveDailyCache(trackIds: ["b1", "b2"], source: "cold_start")

        let musicCached = await music.loadDailyCache()
        let booksCached = await books.loadDailyCache()

        XCTAssertEqual(musicCached, ["m1", "m2", "m3"], "Music shelf must read only its own cache")
        XCTAssertEqual(booksCached, ["b1", "b2"], "Books shelf must read only its own cache")
    }

    // A fresh launch must show the previous session's picks immediately rather
    // than a "Finding…" spinner, and a background refresh that yields nothing
    // must never clobber those previous picks with a spinner/empty state.
    func testShowsPreviousSnapshotInsteadOfSpinnerWhenRefreshYieldsNothing() async {
        await db.saveTracks([
            Track.makeStub(id: "snap1", title: "Snap 1"),
            Track.makeStub(id: "snap2", title: "Snap 2"),
        ])
        let store = MadeForYouShelfStore(db: db, tasteProfileStore: tasteStore, shelf: .books)
        // Simulate a prior session's persisted picks.
        store.saveShelfSnapshot(trackIds: ["snap1", "snap2"], kind: .personalized)

        // No archiveService and no taste profile → the background refresh
        // produces nothing, so the previous snapshot must stay on screen.
        await store.loadIfNeeded(historyVersion: 0)

        guard case .loaded(let kind, let tracks) = store.state else {
            return XCTFail("shelf must show the previous snapshot, not a spinner or empty state")
        }
        XCTAssertEqual(kind, .personalized)
        XCTAssertEqual(tracks.map(\.id), ["snap1", "snap2"])
    }
}
