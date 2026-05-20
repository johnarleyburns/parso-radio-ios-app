import XCTest
@testable import ParsoMusic

final class BookmarkTests: XCTestCase {

    func testNewClampsNegativePosition() {
        let bm = Bookmark.new(trackId: "t1", positionSeconds: -10)
        XCTAssertEqual(bm.positionSeconds, 0)
    }

    func testNewTrimsAndNormalizesEmptyLabel() {
        XCTAssertNil(Bookmark.new(trackId: "t1", positionSeconds: 0, label: "   ").label)
        XCTAssertNil(Bookmark.new(trackId: "t1", positionSeconds: 0, label: "").label)
        XCTAssertEqual(
            Bookmark.new(trackId: "t1", positionSeconds: 0, label: " hello ").label,
            "hello")
    }

    func testNewIdsAreUnique() {
        var ids = Set<String>()
        for _ in 0..<200 {
            ids.insert(Bookmark.new(trackId: "t1", positionSeconds: 0).id)
        }
        XCTAssertEqual(ids.count, 200, "Bookmark ids must be unique (UUIDs).")
    }
}

final class BookmarkDatabaseTests: XCTestCase {

    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    func testSaveAndFetchBookmark() async {
        let bm = Bookmark.new(trackId: "trk1", positionSeconds: 42, label: "spot")
        await db.saveBookmark(bm)
        let loaded = await db.fetchBookmarks(forTrack: "trk1")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, bm.id)
        XCTAssertEqual(loaded.first?.positionSeconds, 42, accuracy: 0.0001)
        XCTAssertEqual(loaded.first?.label, "spot")
    }

    func testFetchBookmarksIsScopedByTrack() async {
        await db.saveBookmark(Bookmark.new(trackId: "a", positionSeconds: 10))
        await db.saveBookmark(Bookmark.new(trackId: "a", positionSeconds: 20))
        await db.saveBookmark(Bookmark.new(trackId: "b", positionSeconds: 5))

        let aBookmarks = await db.fetchBookmarks(forTrack: "a")
        let bBookmarks = await db.fetchBookmarks(forTrack: "b")
        let cBookmarks = await db.fetchBookmarks(forTrack: "c")

        XCTAssertEqual(aBookmarks.count, 2)
        XCTAssertEqual(bBookmarks.count, 1)
        XCTAssertTrue(cBookmarks.isEmpty)
    }

    func testFetchBookmarksIsOrderedByPosition() async {
        await db.saveBookmark(Bookmark.new(trackId: "x", positionSeconds: 300))
        await db.saveBookmark(Bookmark.new(trackId: "x", positionSeconds: 10))
        await db.saveBookmark(Bookmark.new(trackId: "x", positionSeconds: 120))
        let loaded = await db.fetchBookmarks(forTrack: "x").map(\.positionSeconds)
        XCTAssertEqual(loaded, [10, 120, 300],
                       "Bookmarks should be ordered ascending by position_seconds.")
    }

    func testDeleteBookmarkById() async {
        let keep   = Bookmark.new(trackId: "y", positionSeconds: 10)
        let remove = Bookmark.new(trackId: "y", positionSeconds: 20)
        await db.saveBookmark(keep)
        await db.saveBookmark(remove)
        await db.deleteBookmark(id: remove.id)
        let loaded = await db.fetchBookmarks(forTrack: "y").map(\.id)
        XCTAssertEqual(loaded, [keep.id])
    }

    func testDeleteAllBookmarksForTrack() async {
        await db.saveBookmark(Bookmark.new(trackId: "z", positionSeconds: 1))
        await db.saveBookmark(Bookmark.new(trackId: "z", positionSeconds: 2))
        await db.saveBookmark(Bookmark.new(trackId: "z", positionSeconds: 3))
        await db.saveBookmark(Bookmark.new(trackId: "other", positionSeconds: 99))
        await db.deleteAllBookmarks(forTrack: "z")
        XCTAssertTrue(await db.fetchBookmarks(forTrack: "z").isEmpty)
        XCTAssertEqual(await db.fetchBookmarks(forTrack: "other").count, 1,
                       "deleteAllBookmarks must be scoped to one track.")
    }
}

@MainActor
final class BookmarkViewModelTests: XCTestCase {

    private var db: DatabaseService!
    private var vm: PlayerViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: AudioPlayerService(),
            downloadManager: DownloadManager(db: db)
        )
    }

    func testAddBookmarkAtCurrentPosition() async {
        vm.currentTrack = makeTrack(id: "bm-trk")
        vm.currentPosition = 90
        await vm.addBookmarkAtCurrentPosition(label: "Cliffhanger")
        XCTAssertEqual(vm.bookmarksForCurrentTrack.count, 1)
        XCTAssertEqual(vm.bookmarksForCurrentTrack.first?.positionSeconds, 90, accuracy: 0.001)
        XCTAssertEqual(vm.bookmarksForCurrentTrack.first?.label, "Cliffhanger")
    }

    func testAddBookmarkNoopWhenNothingPlaying() async {
        vm.currentTrack = nil
        await vm.addBookmarkAtCurrentPosition()
        XCTAssertTrue(vm.bookmarksForCurrentTrack.isEmpty)
    }

    func testDeleteBookmarkRefreshesList() async {
        vm.currentTrack = makeTrack(id: "bm-trk")
        vm.currentPosition = 10
        await vm.addBookmarkAtCurrentPosition()
        vm.currentPosition = 50
        await vm.addBookmarkAtCurrentPosition()
        XCTAssertEqual(vm.bookmarksForCurrentTrack.count, 2)
        let toDelete = vm.bookmarksForCurrentTrack.first!
        await vm.deleteBookmark(toDelete)
        XCTAssertEqual(vm.bookmarksForCurrentTrack.count, 1)
        XCTAssertNotEqual(vm.bookmarksForCurrentTrack.first?.id, toDelete.id)
    }

    func testSeekToBookmarkRejectsWrongTrack() {
        vm.currentTrack = makeTrack(id: "current")
        let bm = Bookmark.new(trackId: "other", positionSeconds: 60)
        vm.currentPosition = 5
        vm.seekToBookmark(bm)
        // Position should not change: bookmark is for a different track.
        XCTAssertEqual(vm.currentPosition, 5, accuracy: 0.001)
    }

    private func makeTrack(id: String) -> Track {
        Track(
            id: id, source: "fma",
            title: "T", artist: "A",
            duration: 200,
            streamURL: URL(string: "https://example.com/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .cc0, tags: [],
            qualityScore: 1.0,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0
        )
    }
}
