import XCTest
@testable import ParsoMusic

final class AutosaveBookmarkDatabaseTests: XCTestCase {

    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    func testSaveAndFetchAutosave() async throws {
        await db.saveAutosaveBookmark(trackId: "a", positionSeconds: 123.5)
        let auto = await db.fetchAutosaveBookmark(forTrack: "a")
        XCTAssertNotNil(auto)
        XCTAssertEqual(auto?.positionSeconds ?? -1, 123.5, accuracy: 0.001)
        XCTAssertEqual(auto?.isAutosave, true)
        XCTAssertEqual(auto?.id, Bookmark.autosaveId(forTrack: "a"))
    }

    func testAutosaveIsUpsert() async throws {
        await db.saveAutosaveBookmark(trackId: "x", positionSeconds: 10)
        await db.saveAutosaveBookmark(trackId: "x", positionSeconds: 200)
        let auto = await db.fetchAutosaveBookmark(forTrack: "x")
        XCTAssertEqual(auto?.positionSeconds ?? -1, 200, accuracy: 0.001,
            "Saving twice must replace, not duplicate.")
        let all = try await db.allBookmarkRowsForTesting(trackId: "x")
        XCTAssertEqual(all.count, 1, "Only one autosave row per track.")
    }

    func testAutosaveExcludedFromUserBookmarksList() async {
        await db.saveBookmark(Bookmark.new(trackId: "y", positionSeconds: 60, label: "user"))
        await db.saveAutosaveBookmark(trackId: "y", positionSeconds: 90)
        let userBms = await db.fetchBookmarks(forTrack: "y")
        XCTAssertEqual(userBms.count, 1, "User bookmarks list must omit the autosave.")
        XCTAssertEqual(userBms.first?.label, "user")
        let autoY = await db.fetchAutosaveBookmark(forTrack: "y")
        XCTAssertNotNil(autoY)
    }

    func testDeleteAutosave() async {
        await db.saveAutosaveBookmark(trackId: "z", positionSeconds: 50)
        await db.deleteAutosaveBookmark(forTrack: "z")
        let z = await db.fetchAutosaveBookmark(forTrack: "z")
        XCTAssertNil(z)
    }

    func testDeleteAutosaveLeavesUserBookmarksIntact() async {
        await db.saveBookmark(Bookmark.new(trackId: "k", positionSeconds: 10, label: "ch1"))
        await db.saveAutosaveBookmark(trackId: "k", positionSeconds: 80)
        await db.deleteAutosaveBookmark(forTrack: "k")
        let k = await db.fetchAutosaveBookmark(forTrack: "k")
        XCTAssertNil(k)
        let userBms = await db.fetchBookmarks(forTrack: "k")
        XCTAssertEqual(userBms.count, 1, "User bookmarks survive autosave deletion.")
    }

    func testAutosaveIdsAreDeterministic() {
        XCTAssertEqual(Bookmark.autosaveId(forTrack: "abc"), "autosave:abc")
        let a = Bookmark.autosave(trackId: "abc", positionSeconds: 1)
        let b = Bookmark.autosave(trackId: "abc", positionSeconds: 2)
        XCTAssertEqual(a.id, b.id, "Autosave id must depend only on the track id.")
    }
}

@MainActor
final class AutosaveBookmarkViewModelTests: XCTestCase {

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

    func testSaveAutosaveNoOpWhenNothingPlaying() async {
        vm.currentTrack = nil
        vm.saveAutosaveForCurrentTrack()
        try? await Task.sleep(nanoseconds: 30_000_000)
        let none = await db.fetchAutosaveBookmark(forTrack: "anything")
        XCTAssertNil(none)
    }

    func testSaveAutosaveSkipsEarlyPosition() async throws {
        vm.currentTrack = makeTrack(id: "early", duration: 600)
        vm.currentPosition = 3
        vm.saveAutosaveForCurrentTrack()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let early = await db.fetchAutosaveBookmark(forTrack: "early")
        XCTAssertNil(early, "Don't autosave when the user has barely started.")
    }

    func testSaveAutosaveSkipsNearEnd() async throws {
        vm.currentTrack = makeTrack(id: "almost", duration: 300)
        vm.currentPosition = 298
        vm.saveAutosaveForCurrentTrack()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let almost = await db.fetchAutosaveBookmark(forTrack: "almost")
        XCTAssertNil(almost, "Within 5 s of the end is a natural finish — no autosave.")
    }

    func testSaveAutosaveSucceedsInTheMiddle() async throws {
        vm.currentTrack = makeTrack(id: "mid", duration: 600)
        vm.currentPosition = 300
        vm.saveAutosaveForCurrentTrack()
        try? await Task.sleep(nanoseconds: 80_000_000)
        let auto = await db.fetchAutosaveBookmark(forTrack: "mid")
        XCTAssertNotNil(auto)
        XCTAssertEqual(auto?.positionSeconds ?? -1, 300, accuracy: 0.001)
    }

    func testSaveAutosaveSkippedForAmbientLoop() async throws {
        let ambient = Channel.defaults.first { $0.contentType == .ambientLoop }!
        vm.currentChannel = ambient
        vm.currentTrack = makeTrack(id: "ambient-1", duration: 0)
        vm.currentPosition = 60
        vm.saveAutosaveForCurrentTrack()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let amb = await db.fetchAutosaveBookmark(forTrack: "ambient-1")
        XCTAssertNil(amb, "Ambient loops play forever — no autosave.")
    }

    func testTogglePlayPauseAutosavesOnPause() async throws {
        vm.currentTrack = makeTrack(id: "pp", duration: 600)
        vm.currentPosition = 250
        // Mark the audio player as playing so togglePlayPause takes the pause path.
        vm.audioPlayer.isPlaying = true
        vm.togglePlayPause()
        try? await Task.sleep(nanoseconds: 80_000_000)
        let auto = await db.fetchAutosaveBookmark(forTrack: "pp")
        XCTAssertEqual(auto?.positionSeconds ?? -1, 250, accuracy: 0.001,
            "togglePlayPause must autosave when transitioning to paused.")
    }

    private func makeTrack(id: String, duration: Double) -> Track {
        Track(
            id: id, source: "fma",
            title: "T", artist: "A",
            duration: duration,
            streamURL: URL(string: "https://example.com/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .cc0, tags: [],
            qualityScore: 1.0,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0
        )
    }
}

// Test-only probe for "is there more than one row?" — we don't expose internal
// schema in production, but tests need to verify upsert semantics.
extension DatabaseService {
    func allBookmarkRowsForTesting(trackId: String) async throws -> [Bookmark] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[Bookmark], Never>) in
            // Mirror the fetchBookmarks query but include autosaves so we can
            // assert "exactly one autosave row per track".
            Task {
                let user = await self.fetchBookmarks(forTrack: trackId)
                let auto = await self.fetchAutosaveBookmark(forTrack: trackId)
                continuation.resume(returning: user + (auto.map { [$0] } ?? []))
            }
        }
    }
}
