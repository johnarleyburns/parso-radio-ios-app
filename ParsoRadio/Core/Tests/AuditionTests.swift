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

    func test_preAuditionState_preservedAcrossMultipleCalls() async {
        // Set up genuine channel playback
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        let originalTrack = makeTrack("original")
        vm.currentChannel = channel
        vm.currentTrack = originalTrack
        vm.isPlaying = true
        vm.currentPosition = 45.0

        // First audition call saves the channel context
        await vm.auditionTrack(makeTrack("candidate-1"))

        // Verify the preAuditionState was saved
        vm.stopAudition()
        // The state should be restored — channel should be back
        XCTAssertEqual(vm.currentChannel?.id, "guitar-classical",
            "preAuditionState should restore the original channel after stopAudition")
    }

    func test_preAuditionState_notOverwrittenBySecondCall() async {
        // Set up genuine channel playback
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        let originalTrack = makeTrack("original")
        vm.currentChannel = channel
        vm.currentTrack = originalTrack
        vm.isPlaying = true
        vm.currentPosition = 30.0

        // First audition
        await vm.auditionTrack(makeTrack("candidate-1"))
        // preAuditionState should hold channel=guitar-classical, track=original, position=30.0

        // Simulate current state being cleared (which auditionTrack does)
        // The second call would have captured (nil, nil, ...) before the fix
        await vm.auditionTrack(makeTrack("candidate-2"))
        // After fix: preAuditionState is still the original, not (nil, nil, ...)

        vm.stopAudition()
        // After stop, the original channel should be restored
        XCTAssertEqual(vm.currentChannel?.id, "guitar-classical",
            "preAuditionState must NOT be overwritten by second auditionTrack call")
    }

    // MARK: - stopAuditionWithoutRestore

    func test_stopAuditionWithoutRestore_clearsAuditionAndDiscardsPreState() async {
        // Set up genuine channel playback as pre-audition state
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        let originalTrack = makeTrack("original")
        vm.currentChannel = channel
        vm.currentTrack = originalTrack
        vm.isPlaying = true
        vm.currentPosition = 30.0

        // Start audition
        await vm.auditionTrack(makeTrack("candidate-1"))

        // stopAuditionWithoutRestore must clear the audition AND discard preAuditionState
        vm.stopAuditionWithoutRestore()

        XCTAssertNil(vm.currentTrack, "audition track must be cleared")
        XCTAssertFalse(vm.isLoading, "spinner must be off")
        XCTAssertFalse(vm.isPlaying, "playback must stop")
        // preAuditionState is discarded, so NO channel is restored
        XCTAssertNil(vm.currentChannel,
            "stopAuditionWithoutRestore must discard preAuditionState — no channel restoration")
    }

    func test_stopAuditionWithoutRestore_doesNotDisturbChannelPlayback() {
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        vm.currentChannel = channel
        vm.currentTrack = makeTrack("ch1")
        vm.isPlaying = true

        vm.stopAuditionWithoutRestore()

        XCTAssertEqual(vm.currentTrack?.id, "ch1",
            "stopAuditionWithoutRestore must NOT touch genuine channel playback")
        XCTAssertTrue(vm.isPlaying)
        XCTAssertNotNil(vm.currentChannel)
    }

    func test_stopAuditionWithoutRestore_isIdempotent() {
        vm.stopAuditionWithoutRestore()
        XCTAssertNil(vm.currentTrack)
    }
}
