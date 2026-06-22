import XCTest
@testable import ParsoMusic

@MainActor
final class NowPlayingSheetTests: XCTestCase {

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
        UserDefaults.standard.removeObject(forKey: "shuffleMode")
        UserDefaults.standard.removeObject(forKey: "repeatMode")
    }

    override func tearDownWithError() throws {
        vm = nil
        db = nil
        UserDefaults.standard.removeObject(forKey: "shuffleMode")
        UserDefaults.standard.removeObject(forKey: "repeatMode")
        try super.tearDownWithError()
    }

    // MARK: - Kind switching

    func testMusicKindRendersMusicControlsCondition() {
        let channel = Channel(
            id: "music-test", name: "Music", category: "Curated",
            icon: "music.note", contentType: .music
        )
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "track1", title: "Test Song")

        XCTAssertEqual(vm.currentChannel?.mediaKind, .music)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNotNil(vm.currentTrack)
    }

    func testAudiobookKindRendersSpokenControlsCondition() {
        let channel = Channel(
            id: "audiobook-test", name: "Audiobook", category: "Audiobooks",
            icon: "book.fill", contentType: .spokenWord
        )
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "track1", title: "Chapter 1", parentIdentifier: "book1")

        XCTAssertEqual(vm.currentChannel?.mediaKind, .audiobook)
    }

    func testLectureKindRendersSpokenControlsWithLectureFlag() {
        let channel = Channel(
            id: "lecture-test", name: "Lecture", category: "Lectures",
            icon: "building.columns.fill", contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        )
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "lec1", title: "Lecture 1")

        let kind = vm.currentChannel?.mediaKind ?? .music
        XCTAssertEqual(kind, .lecture)
    }

    func testPodcastKindRendersPodcastControlsCondition() {
        let channel = Channel(
            id: "podcast-test", name: "Podcast", category: "Podcasts",
            icon: "newspaper.fill", contentType: .spokenWord,
            feedURL: "https://example.com/feed.xml"
        )
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "ep1", title: "Episode 1")

        XCTAssertEqual(vm.currentChannel?.mediaKind, .podcast)
    }

    func testAmbientKindRendersAmbientControlsCondition() {
        let channel = Channel(
            id: "ambient-test", name: "Ambient", category: "Ambient",
            icon: "leaf.fill", contentType: .ambientLoop
        )
        vm.currentChannel = channel

        let kind = vm.currentChannel?.mediaKind ?? .music
        XCTAssertEqual(kind, .ambient)
    }

    // MARK: - Disabled state

    func testControlsDisabledWhenNoTrackAndNotAmbient() {
        let channel = Channel(
            id: "music-test", name: "Music", category: "Curated",
            icon: "music.note", contentType: .music
        )
        vm.currentChannel = channel
        vm.currentTrack = nil

        let kind = vm.currentChannel?.mediaKind ?? .music
        let disabled = (vm.currentTrack == nil || vm.isLoading) && kind != .ambient

        XCTAssertTrue(disabled)
    }

    func testControlsDisabledDuringBuffering() {
        let channel = Channel(
            id: "music-test", name: "Music", category: "Curated",
            icon: "music.note", contentType: .music
        )
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "track1", title: "Test")
        vm.isLoading = true

        let kind = vm.currentChannel?.mediaKind ?? .music
        let disabled = (vm.currentTrack == nil || vm.isLoading) && kind != .ambient

        XCTAssertTrue(disabled, "Controls should be disabled during buffering even when a track exists")
        XCTAssertTrue(vm.isLoading)
        XCTAssertNotNil(vm.currentTrack)
    }

    func testControlsEnabledWhenLoadedAndHasTrack() {
        let channel = Channel(
            id: "music-test", name: "Music", category: "Curated",
            icon: "music.note", contentType: .music
        )
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "track1", title: "Test")
        vm.isLoading = false

        let kind = vm.currentChannel?.mediaKind ?? .music
        let disabled = (vm.currentTrack == nil || vm.isLoading) && kind != .ambient

        XCTAssertFalse(disabled)
    }

    func testAmbientControlsEnabledWithoutTrack() {
        let channel = Channel(
            id: "ambient-test", name: "Ambient", category: "Ambient",
            icon: "leaf.fill", contentType: .ambientLoop
        )
        vm.currentChannel = channel
        vm.currentTrack = nil
        vm.isLoading = false

        let kind = vm.currentChannel?.mediaKind ?? .music
        let disabled = (vm.currentTrack == nil || vm.isLoading) && kind != .ambient

        XCTAssertFalse(disabled, "Ambient controls should remain enabled even without a track")
        XCTAssertEqual(kind, .ambient)
    }

    func testAmbientControlsEnabledDuringBuffering() {
        let channel = Channel(
            id: "ambient-test", name: "Ambient", category: "Ambient",
            icon: "leaf.fill", contentType: .ambientLoop
        )
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "amb1", title: "Ambient Sound")
        vm.isLoading = true

        let kind = vm.currentChannel?.mediaKind ?? .music
        let disabled = (vm.currentTrack == nil || vm.isLoading) && kind != .ambient

        XCTAssertFalse(disabled, "Ambient controls should remain enabled during buffering")
        XCTAssertEqual(kind, .ambient)
    }

    // MARK: - Overflow menu conditions

    func testOverflowMenuHasBookSkipForAudiobook() {
        let channel = Channel(
            id: "audiobook-test", name: "Audiobook", category: "Audiobooks",
            icon: "book.fill", contentType: .spokenWord
        )
        vm.currentChannel = channel

        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsBookSkip = kind == .audiobook || kind == .lecture
        XCTAssertTrue(showsBookSkip)
    }

    func testOverflowMenuHasBookSkipForLecture() {
        let channel = Channel(
            id: "lecture-test", name: "Lecture", category: "Lectures",
            icon: "building.columns.fill", contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        )
        vm.currentChannel = channel

        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsBookSkip = kind == .audiobook || kind == .lecture
        XCTAssertTrue(showsBookSkip)
    }

    func testOverflowMenuNoBookSkipForMusic() {
        let channel = Channel(
            id: "music-test", name: "Music", category: "Curated",
            icon: "music.note", contentType: .music
        )
        vm.currentChannel = channel

        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsBookSkip = kind == .audiobook || kind == .lecture
        XCTAssertFalse(showsBookSkip)
    }

    func testOverflowMenuNoBookSkipForPodcast() {
        let channel = Channel(
            id: "podcast-test", name: "Podcast", category: "Podcasts",
            icon: "newspaper.fill", contentType: .spokenWord,
            feedURL: "https://example.com/feed.xml"
        )
        vm.currentChannel = channel

        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsBookSkip = kind == .audiobook || kind == .lecture
        XCTAssertFalse(showsBookSkip)
    }

    // MARK: - Overflow menu: sleep timer for music and ambient

    func testOverflowMenuHasSleepTimerForMusic() {
        let channel = Channel(
            id: "music-test", name: "Music", category: "Curated",
            icon: "music.note", contentType: .music
        )
        vm.currentChannel = channel

        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsSleepInOverflow = kind == .music || kind == .ambient
        XCTAssertTrue(showsSleepInOverflow)
    }

    func testOverflowMenuHasSleepTimerForAmbient() {
        let channel = Channel(
            id: "ambient-test", name: "Ambient", category: "Ambient",
            icon: "leaf.fill", contentType: .ambientLoop
        )
        vm.currentChannel = channel

        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsSleepInOverflow = kind == .music || kind == .ambient
        XCTAssertTrue(showsSleepInOverflow)
    }

    func testOverflowMenuNoSleepTimerForPodcast() {
        let channel = Channel(
            id: "podcast-test", name: "Podcast", category: "Podcasts",
            icon: "newspaper.fill", contentType: .spokenWord,
            feedURL: "https://example.com/feed.xml"
        )
        vm.currentChannel = channel

        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsSleepInOverflow = kind == .music || kind == .ambient
        XCTAssertFalse(showsSleepInOverflow)
    }

    // MARK: - Overflow menu: Add to playlist gated to Music only

    func testAddToPlaylistOnlyForMusic() {
        let channel = Channel(
            id: "music-test", name: "Music", category: "Curated",
            icon: "music.note", contentType: .music
        )
        vm.currentChannel = channel
        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsAddToPlaylist = kind == .music
        XCTAssertTrue(showsAddToPlaylist)
    }

    func testAddToPlaylistAbsentForAudiobook() {
        let channel = Channel(
            id: "audiobook-test", name: "Audiobook", category: "Audiobooks",
            icon: "book.fill", contentType: .spokenWord
        )
        vm.currentChannel = channel
        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsAddToPlaylist = kind == .music
        XCTAssertFalse(showsAddToPlaylist)
    }

    func testAddToPlaylistAbsentForAmbient() {
        let channel = Channel(
            id: "ambient-test", name: "Ambient", category: "Ambient",
            icon: "leaf.fill", contentType: .ambientLoop
        )
        vm.currentChannel = channel
        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsAddToPlaylist = kind == .music
        XCTAssertFalse(showsAddToPlaylist)
    }

    func testAddToPlaylistAbsentForPodcast() {
        let channel = Channel(
            id: "podcast-test", name: "Podcast", category: "Podcasts",
            icon: "newspaper.fill", contentType: .spokenWord,
            feedURL: "https://example.com/feed.xml"
        )
        vm.currentChannel = channel
        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsAddToPlaylist = kind == .music
        XCTAssertFalse(showsAddToPlaylist)
    }

    func testAddToPlaylistAbsentForLecture() {
        let channel = Channel(
            id: "lecture-test", name: "Lecture", category: "Lectures",
            icon: "building.columns.fill", contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        )
        vm.currentChannel = channel
        let kind = vm.currentChannel?.mediaKind ?? .music
        let showsAddToPlaylist = kind == .music
        XCTAssertFalse(showsAddToPlaylist)
    }
}
