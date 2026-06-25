import XCTest
@testable import ParsoMusic

/// Issues #3 and #4: resuming a book from "Jump back in" must play the WHOLE
/// book from its saved position and render the audiobook surface — never the
/// music surface — and a single search play must carry its real media kind.
@MainActor
final class SurfaceKindResumeTests: XCTestCase {
    private var db: DatabaseService!
    private var engine: FakeAudioEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        engine = FakeAudioEngine()
        for k in ["session.kind", "session.contextId", "session.trackId",
                  "session.position", "lastChannelId"] {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    private func makeVM() -> PlayerViewModel {
        PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: engine,
            downloadManager: DownloadManager(db: db),
            loadTimeout: 0.05,
            stallTimeout: 5.0
        )
    }

    private func bookChapter(_ n: Int) -> Track {
        var t = Track.makeStub(id: "bk/ch_\(n).mp3", title: "Chapter \(n)",
                               parentIdentifier: "bk")
        t.partNumber = n
        t.collectionTitle = "Gallipoli"
        return t
    }

    private func settle(_ ms: UInt64 = 60) async {
        for _ in 0..<6 { await Task.yield() }
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
        for _ in 0..<6 { await Task.yield() }
    }

    func testResumeWorkPlaysWholeBookFromSavedPositionOnAudiobookSurface() async throws {
        let vm = makeVM()
        let chapters = [bookChapter(1), bookChapter(2), bookChapter(3)]
        await db.saveTracks(chapters)
        await db.savePosition(
            channelId: PlayerViewModel.bookPositionKey(parentIdentifier: "bk"),
            trackId: chapters[1].id, seconds: 50)

        let work = RecentWork(id: "work:bk", track: chapters[0],
                              mediaKind: .audiobook, playsWholeWork: true)
        await vm.playRecentWork(work)
        await settle()

        XCTAssertEqual(vm.activeMediaKind, .audiobook,
                       "a resumed book must render the audiobook surface, not music")
        XCTAssertEqual(vm.currentTrack?.id, chapters[1].id,
                       "resume jumps to the saved chapter")
        XCTAssertEqual(engine.lastStartAt, 50, accuracy: 1.0,
                       "resume seeks to the saved position")
        XCTAssertEqual(vm.playlistTracks.count, 3, "the whole book is queued")
    }

    func testSearchResultMediaKindDrivesSurface() async throws {
        let vm = makeVM()
        let group = SearchViewModel.ResultGroup(
            id: "spoken-1", title: "A Spoken Work", creator: "Author",
            addedDate: nil, duration: 600, collection: "librivoxaudio")
        await vm.playSearchResult(group, mediaKind: .audiobook)
        await settle()
        XCTAssertEqual(vm.activeMediaKind, .audiobook,
                       "a single spoken search result must not render the music surface")
    }
}
