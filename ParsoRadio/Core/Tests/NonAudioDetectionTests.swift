import XCTest
@testable import ParsoMusic

/// Tests that non-audio tracks are handled properly: the stall watchdog
/// fires, error message is set, and the spinner is cleared so the curator
/// doesn't see "spins forever" with no feedback.
final class NonAudioDetectionTests: XCTestCase {

    /// When a curator audition track stalls (never produces audio), the
    /// stall watchdog should fire, set errorMessage, clear isLoading, and
    /// clear currentTrack. This prevents the "spins forever with no toast"
    /// bug where the curator keeps retrying the same broken track.
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
            stallTimeout: 1) // 1 second for fast test

        let track = Track(
            id: "stall-test", source: "internet_archive",
            title: "Stall Test", artist: "Test",
            duration: 100, // > 0.5s so duration check doesn't fire early
            streamURL: URL(string: "https://archive.org/download/test")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1, rawCreator: "Test",
            composer: nil, instruments: [],
            metadataConfidence: 1)

        // Start audition — arms the 1-second stall watchdog since FakeEngine
        // never produces time ticks
        await vm.auditionTrack(track)

        // Wait for stall watchdog
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        XCTAssertNotNil(vm.errorMessage,
            "Stall should set error message so curator sees feedback")
        XCTAssertFalse(vm.isLoading,
            "Stall should clear spinner so curator isn't stuck")
        XCTAssertNil(vm.currentTrack,
            "Stall should clear currentTrack in audition mode")
    }
}
