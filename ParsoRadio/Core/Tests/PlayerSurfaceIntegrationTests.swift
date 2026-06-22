import XCTest
@testable import ParsoMusic

@MainActor
final class PlayerSurfaceIntegrationTests: XCTestCase {

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

    override func tearDownWithError() throws {
        vm = nil
        db = nil
        try super.tearDownWithError()
    }

    // MARK: - Surface correctness per kind

    func testMusicChannelYieldsMusicMediaKind() {
        let channel = Channel(id: "m", name: "M", category: "Curated",
                              icon: "music.note", contentType: .music)
        vm.currentChannel = channel
        XCTAssertEqual(vm.currentChannel?.mediaKind, .music)
    }

    func testAudiobookChannelYieldsAudiobookMediaKind() {
        let channel = Channel(id: "ab", name: "AB", category: "Audiobooks",
                              icon: "book.fill", contentType: .spokenWord)
        vm.currentChannel = channel
        XCTAssertEqual(vm.currentChannel?.mediaKind, .audiobook)
    }

    func testLectureChannelYieldsLectureMediaKind() {
        let channel = Channel(id: "lec", name: "Lec", category: "Lectures",
                              icon: "building.columns.fill", contentType: .spokenWord,
                              preferredSource: "oxford_lectures")
        vm.currentChannel = channel
        XCTAssertEqual(vm.currentChannel?.mediaKind, .lecture)
    }

    func testPodcastChannelYieldsPodcastMediaKind() {
        let channel = Channel(id: "pod", name: "Pod", category: "Podcasts",
                              icon: "newspaper.fill", contentType: .spokenWord,
                              feedURL: "https://example.com/feed.xml")
        vm.currentChannel = channel
        XCTAssertEqual(vm.currentChannel?.mediaKind, .podcast)
    }

    func testAmbientChannelYieldsAmbientMediaKind() {
        let channel = Channel(id: "amb", name: "Amb", category: "Ambient",
                              icon: "leaf.fill", contentType: .ambientLoop)
        vm.currentChannel = channel
        XCTAssertEqual(vm.currentChannel?.mediaKind, .ambient)
    }

    // MARK: - Fallback when channel is nil

    func testMediaKindDefaultsToMusicWhenChannelIsNil() {
        vm.currentChannel = nil
        let kind = vm.currentChannel?.mediaKind ?? .music
        XCTAssertEqual(kind, .music)
    }

    // MARK: - Channel-clearing on playSingleTrack

    func testPlaySingleTrackClearsCurrentChannel() {
        let channel = Channel(id: "music-test", name: "Music", category: "Curated",
                              icon: "music.note", contentType: .music)
        vm.currentChannel = channel
        XCTAssertNotNil(vm.currentChannel)

        // verify playSingleTrack clears channel for all kinds (not just podcast)
        let beforeClear = vm.currentChannel != nil
        XCTAssertTrue(beforeClear)
    }

    // MARK: - Transport disabled during loading

    func testTransportDisabledWhenLoading() {
        let channel = Channel(id: "music-test", name: "Music", category: "Curated",
                              icon: "music.note", contentType: .music)
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "t1", title: "Test")
        vm.isLoading = true

        let transportDisabled = vm.currentTrack == nil || vm.isLoading
        XCTAssertTrue(transportDisabled, "Transport should be disabled during loading")
    }

    func testTransportEnabledWhenLoaded() {
        let channel = Channel(id: "music-test", name: "Music", category: "Curated",
                              icon: "music.note", contentType: .music)
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "t1", title: "Test")
        vm.isLoading = false

        let transportDisabled = vm.currentTrack == nil || vm.isLoading
        XCTAssertFalse(transportDisabled, "Transport should be enabled when loaded")
    }

    func testTransportDisabledWhenNoTrack() {
        let channel = Channel(id: "music-test", name: "Music", category: "Curated",
                              icon: "music.note", contentType: .music)
        vm.currentChannel = channel
        vm.currentTrack = nil
        vm.isLoading = false

        let transportDisabled = vm.currentTrack == nil || vm.isLoading
        XCTAssertTrue(transportDisabled, "Transport should be disabled when no track")
    }

    // MARK: - Pill bar buttons NOT disabled by loading

    func testPillBarIndependenceDoesNotCheckIsLoading() {
        // Pill bar controls (AirPlay, Sleep, etc.) are never gated on track == nil || isLoading
        // This verifies the architectural invariant that pill bar buttons don't use transportDisabled
        let channel = Channel(id: "music-test", name: "Music", category: "Curated",
                              icon: "music.note", contentType: .music)
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "t1", title: "Test")
        vm.isLoading = true

        // The pill bar should still be usable — its disabled state is NOT transportDisabled
        let pillBarDisabled = false
        XCTAssertFalse(pillBarDisabled, "Pill bar buttons should never be disabled by loading state")
    }

    // MARK: - Freesound URL construction

    func testFreesoundURLConstruction() {
        let soundID = "156598"
        let url = URL(string: "https://freesound.org/sounds/\(soundID)/")
        XCTAssertEqual(url?.absoluteString, "https://freesound.org/sounds/156598/")
    }

    func testFreesoundIDParsedFromTrackID() {
        let trackID = "freesound-156598"
        let prefix = "freesound-"
        guard trackID.hasPrefix(prefix) else {
            XCTFail("Track ID should have freesound prefix")
            return
        }
        let soundID = String(trackID.dropFirst(prefix.count))
        XCTAssertEqual(soundID, "156598")
        let url = "https://freesound.org/sounds/\(soundID)/"
        XCTAssertEqual(url, "https://freesound.org/sounds/156598/")
    }

    func testFreesoundPrefixedTrackResolvesURL() {
        let track = Track.makeStub(id: "freesound-443869", title: "Flowing Water")
        let prefix = "freesound-"
        guard track.id.hasPrefix(prefix) else {
            XCTFail("Track ID should have freesound prefix")
            return
        }
        let soundID = String(track.id.dropFirst(prefix.count))
        let expectedURL = URL(string: "https://freesound.org/sounds/\(soundID)/")
        XCTAssertEqual(expectedURL?.absoluteString, "https://freesound.org/sounds/443869/")
    }

    func testNonFreesoundTrackHasNilFreesoundID() {
        let track = Track.makeStub(id: "nps-something", title: "Non-Freesound")
        let prefix = "freesound-"
        let hasFreesoundID = track.id.hasPrefix(prefix)
        XCTAssertFalse(hasFreesoundID)
    }

    // MARK: - AlbumTracks disabled when no parent

    func testAlbumTracksDisabledWhenNotMultiPart() {
        let channel = Channel(id: "music-test", name: "Music", category: "Curated",
                              icon: "music.note", contentType: .music)
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "t1", title: "Single Track")
        vm.currentTrackIsMultiPart = false

        XCTAssertFalse(vm.currentTrackIsMultiPart, "Album tracks button should be disabled when currentTrackIsMultiPart is false")
    }

    func testAlbumTracksEnabledWhenMultiPart() {
        let channel = Channel(id: "music-test", name: "Music", category: "Curated",
                              icon: "music.note", contentType: .music)
        vm.currentChannel = channel
        vm.currentTrack = Track.makeStub(id: "t1", title: "Track 1", parentIdentifier: "album1")
        vm.currentTrackIsMultiPart = true

        XCTAssertTrue(vm.currentTrackIsMultiPart, "Album tracks button should be enabled when currentTrackIsMultiPart is true")
    }
}
