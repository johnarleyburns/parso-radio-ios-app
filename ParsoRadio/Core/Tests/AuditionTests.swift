import XCTest
@testable import ParsoMusic

/// Tests the "audition context" lifecycle hooks used by Curator Mode — stop on
/// curator-screen exit / app background, no disturbance of genuine
/// channel/playlist playback.
@MainActor
final class AuditionTests: XCTestCase {
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

    private func makePlaylist() -> Playlist {
        Playlist(
            id: UUID().uuidString,
            name: "P",
            createdAt: Date(),
            updatedAt: Date(),
            isFavorites: false,
            isKidSafe: false
        )
    }

    func test_stopAudition_clearsAuditionContext() {
        vm.currentChannel = nil
        vm.currentPlaylist = nil
        vm.currentTrack = makeTrack("a1")
        vm.isLoading = true
        vm.loadingMessage = "Loading…"

        vm.stopAudition()

        XCTAssertNil(vm.currentTrack, "audition context must clear when stopped")
        XCTAssertFalse(vm.isLoading, "spinner must come down")
        XCTAssertNil(vm.loadingMessage)
        XCTAssertFalse(vm.isPlaying)
    }

    func test_stopAudition_doesNotDisturbChannelPlayback() {
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        vm.currentChannel = channel
        vm.currentTrack = makeTrack("ch1")
        vm.isPlaying = true

        vm.stopAudition()

        XCTAssertEqual(vm.currentTrack?.id, "ch1",
            "stopAudition must NOT touch genuine channel playback")
        XCTAssertTrue(vm.isPlaying)
        XCTAssertNotNil(vm.currentChannel)
    }

    func test_stopAudition_doesNotDisturbPlaylistPlayback() {
        vm.currentPlaylist = makePlaylist()
        vm.currentTrack = makeTrack("pl1")
        vm.isPlaying = true

        vm.stopAudition()

        XCTAssertEqual(vm.currentTrack?.id, "pl1",
            "stopAudition must NOT touch genuine playlist playback")
        XCTAssertTrue(vm.isPlaying)
        XCTAssertNotNil(vm.currentPlaylist)
    }

    func test_stopAudition_isIdempotent() {
        // No current track, no channel, no playlist → noop, no crash.
        vm.stopAudition()
        XCTAssertNil(vm.currentTrack)
    }
}
