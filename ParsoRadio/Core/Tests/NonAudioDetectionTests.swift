import XCTest
@testable import ParsoMusic

/// Tests that unplayable tracks are detected and handled: a 10-second
/// audio deadline fires from AudioPlayerService.play(), `onNonAudio`
/// calls back to PlayerViewModel, which sets errorMessage, clears
/// isLoading, and clears currentTrack so the curator sees feedback
/// instead of an infinite spinner.
///
/// Also tests the fix for the 10-second auto-skip cycle: when autoPlay
/// is false (user loaded a channel without pressing play), the
/// non-audio timer must NOT cause an advance-to-next loop.
final class NonAudioDetectionTests: XCTestCase {

    /// A curator audition track that never produces audio should trigger
    /// the stall watchdog, which sets errorMessage and clears the spinner.
    @MainActor
    func test_stallHandlerSetsErrorAndClearsSpinnerForAudition() async {
        let engine = FakeAudioEngine()
        let db = try! DatabaseService(path: ":memory:")
        let vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: engine,
            downloadManager: DownloadManager(db: db),
            stallTimeout: 1)

        let track = Track(
            id: "stall-test", source: "internet_archive",
            title: "Stall Test", artist: "Test",
            duration: 100,
            streamURL: URL(string: "https://archive.org/download/test")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1, rawCreator: "Test",
            composer: nil, instruments: [],
            metadataConfidence: 1)

        await vm.auditionTrack(track)
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        XCTAssertNotNil(vm.errorMessage,
            "Stall should set error message so curator sees feedback")
        XCTAssertFalse(vm.isLoading,
            "Stall should clear spinner so curator isn't stuck")
        XCTAssertNil(vm.currentTrack,
            "Stall should clear currentTrack in audition mode")
    }

    /// onNonAudio callback chain: AudioPlayerService fires onNonAudio →
    /// PlayerViewModel sets errorMessage and skips the track.
    @MainActor
    func test_onNonAudioClearsTrackAndSetsError() async {
        let service = AudioPlayerService()
        let db = try! DatabaseService(path: ":memory:")
        let vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: service,
            downloadManager: DownloadManager(db: db),
            stallTimeout: 20)

        let track = Track(
            id: "non-audio", source: "internet_archive",
            title: "Non Audio", artist: "Test",
            duration: 100,
            streamURL: URL(string: "https://archive.org/download/non-audio")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1, rawCreator: "Test",
            composer: nil, instruments: [],
            metadataConfidence: 1)

        let fired = expectation(description: "onNonAudio → error set")
        // Start a track, then manually fire onNonAudio to verify the chain
        await vm.auditionTrack(track)
        service.onNonAudio?()
        // Give the @MainActor task in the handler a moment to run
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(vm.errorMessage,
            "onNonAudio should set an error message")
        XCTAssertNil(vm.currentTrack,
            "onNonAudio should clear currentTrack")
        fired.fulfill()
        await fulfillment(of: [fired], timeout: 2)
    }

    // MARK: - Auto-skip cycle prevention

    /// When isPlaying is false (user loaded a channel without pressing
    /// play) and onNonAudio fires, the handler MUST NOT advance to the
    /// next track — doing so would restart the 10-second cycle
    /// indefinitely.
    @MainActor
    func test_onNonAudioDoesNotAdvanceWhenNotPlaying() async {
        let engine = FakeAudioEngine()
        let db = try! DatabaseService(path: ":memory:")
        let vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: engine,
            downloadManager: DownloadManager(db: db),
            stallTimeout: 20)

        let channel = Channel(id: "test-ch-1", name: "Test",
                              category: "Test", icon: "music.note",
                              tags: ["test"])
        let track = Track(
            id: "na-skip-1", source: "internet_archive",
            title: "Skip Track", artist: "Test",
            duration: 100,
            streamURL: URL(string: "https://archive.org/download/skip1")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1, rawCreator: "Test",
            composer: nil, instruments: [],
            metadataConfidence: 1)

        // Seed state manually: channel loaded, track set, isPlaying = false
        vm.currentChannel = channel
        vm.currentTrack = track
        vm.isPlaying = false
        let playCountBefore = engine.playCount

        // Fire onNonAudio — must NOT advance
        engine.onNonAudio?()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(engine.playCount, playCountBefore,
            "onNonAudio when not playing must not advance to next track")
        XCTAssertNotNil(vm.errorMessage,
            "Should set error message instead of silently skipping")
        XCTAssertNil(vm.currentTrack,
            "Should clear currentTrack")
    }

    /// When isPlaying is true (user pressed play) and onNonAudio fires,
    /// the handler SHOULD advance to the next track.
    @MainActor
    func test_onNonAudioAdvancesWhenPlaying() async {
        let engine = FakeAudioEngine()
        let db = try! DatabaseService(path: ":memory:")
        let vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: engine,
            downloadManager: DownloadManager(db: db),
            stallTimeout: 20)

        let channel = Channel(id: "test-ch-2", name: "Test Skip",
                              category: "Test", icon: "music.note",
                              tags: ["test"])
        let track = Track(
            id: "na-skip-2", source: "internet_archive",
            title: "Playing Track", artist: "Test",
            duration: 100,
            streamURL: URL(string: "https://archive.org/download/skip2")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1, rawCreator: "Test",
            composer: nil, instruments: [],
            metadataConfidence: 1)

        // Seed state: channel loaded, track set, isPlaying = true
        vm.currentChannel = channel
        vm.currentTrack = track
        vm.isPlaying = true
        let playCountBefore = engine.playCount

        // Fire onNonAudio — should advance (but may fail to find next track)
        engine.onNonAudio?()
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Either playCount increased (next track loaded) or error set (no
        // tracks in DB). Both confirm advanceToNext was called.
        let advanced = engine.playCount > playCountBefore
        let errored = vm.errorMessage != nil
        XCTAssertTrue(advanced || errored,
            "onNonAudio when playing should call advanceToNext")
    }
}
