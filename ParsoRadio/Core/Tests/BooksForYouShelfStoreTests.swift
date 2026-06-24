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
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "tasteProfileBackfillVersion")
        db = nil
        tasteStore = nil
        super.tearDown()
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
}
