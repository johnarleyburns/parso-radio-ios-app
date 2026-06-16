import XCTest
@testable import ParsoMusic

/// Tests the pure helper that drives "Kids Mode just turned on" — the audit
/// item from NAVIGATION-AUDIT-KIDS-MODE.md asking for a scripted proof that
/// playHistory is cleared, kid-safe playlists are preserved, and non-kid
/// contexts always redirect.
@MainActor
final class KidsModeEnterTests: XCTestCase {
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
            audioPlayer: FakeAudioEngine(),
            downloadManager: DownloadManager(db: db)
        )
    }

    private func nonKidsChannel() -> Channel {
        Channel.defaults.first { $0.id == "guitar-classical" }!
    }

    private func kidsChannel() -> Channel {
        Channel.defaults.first { $0.id == "childrens-songs" }!
    }

    private func makePlaylist(isKidSafe: Bool) -> Playlist {
        Playlist(
            id: UUID().uuidString,
            name: "Test",
            createdAt: Date(),
            updatedAt: Date(),
            isFavorites: false,
            isKidSafe: isKidSafe
        )
    }

    private func makeTrack(_ id: String) -> Track {
        Track(
            id: id, source: "fma", title: "T \(id)", artist: "A",
            duration: 100,
            streamURL: URL(string: "https://freemusicarchive.org/\(id)")!,
            downloadURL: nil, localFilePath: nil, license: .cc0, tags: [],
            qualityScore: 1, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 1
        )
    }

    func test_enterKidsMode_clearsHistoryAndRedirectsFromNonKidsChannel() {
        vm.currentChannel = nonKidsChannel()
        vm.playHistory = [makeTrack("h1"), makeTrack("h2")]
        let target = vm.enterKidsMode()
        XCTAssertTrue(vm.playHistory.isEmpty,
            "history must clear so back-track can't reach pre-Kids-Mode tracks")
        XCTAssertNotNil(target, "must redirect from a non-kids channel")
        XCTAssertTrue(KidsModeController.allowedChannelIDs.contains(target?.id ?? ""),
            "redirect target must be a kids channel")
    }

    func test_enterKidsMode_clearsHistoryAndStaysWhenAlreadyOnKidsChannel() {
        vm.currentChannel = kidsChannel()
        vm.playHistory = [makeTrack("h1")]
        let target = vm.enterKidsMode()
        XCTAssertTrue(vm.playHistory.isEmpty, "history is cleared on every enter")
        XCTAssertNil(target, "must NOT redirect when already on a kids channel")
    }

    func test_enterKidsMode_preservesKidSafePlaylist() {
        vm.currentPlaylist = makePlaylist(isKidSafe: true)
        vm.playHistory = [makeTrack("h1")]
        let target = vm.enterKidsMode()
        XCTAssertTrue(vm.playHistory.isEmpty)
        XCTAssertNil(target,
            "kid-safe playlist context must be preserved (parent can hand the phone over without interrupting an already-curated kid playlist)")
    }

    func test_enterKidsMode_redirectsAwayFromNonKidSafePlaylist() {
        vm.currentPlaylist = makePlaylist(isKidSafe: false)
        let target = vm.enterKidsMode()
        XCTAssertNotNil(target,
            "non-kid-safe playlist must redirect to a kids channel")
        XCTAssertTrue(KidsModeController.allowedChannelIDs.contains(target?.id ?? ""))
    }

    func test_enterKidsMode_clearsHistoryEvenWhenStaying() {
        vm.currentChannel = kidsChannel()
        vm.playHistory = [makeTrack("h1"), makeTrack("h2"), makeTrack("h3")]
        _ = vm.enterKidsMode()
        XCTAssertTrue(vm.playHistory.isEmpty,
            "history must clear unconditionally — even when staying on a kids channel — so a stray pre-Kids-Mode entry can never resurface")
    }
}
