import XCTest
@testable import ParsoMusic

/// Tests that unplayable tracks are detected and handled: a 10-second
/// audio deadline fires from AudioPlayerService.play(), `onNonAudio`
/// calls back to PlayerViewModel, which sets errorMessage, clears
/// isLoading, and clears currentTrack so the curator sees feedback
/// instead of an infinite spinner.
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
}
