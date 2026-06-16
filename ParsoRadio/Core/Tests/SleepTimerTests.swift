import XCTest
@testable import ParsoMusic

@MainActor
final class SleepTimerTests: XCTestCase {

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

    func testStartSleepTimerSetsEndsAt() {
        let before = Date()
        vm.startSleepTimer(minutes: 30)
        XCTAssertNotNil(vm.sleepTimerEndsAt)
        XCTAssertTrue(vm.isSleepTimerActive)
        let elapsed = vm.sleepTimerEndsAt!.timeIntervalSince(before)
        XCTAssertGreaterThan(elapsed, 30 * 60 - 1,
                             "End time should be ~30 minutes from now.")
        XCTAssertLessThan(elapsed, 30 * 60 + 1)
    }

    func testStartSleepTimerWithZeroIsNoop() {
        vm.startSleepTimer(minutes: 0)
        XCTAssertNil(vm.sleepTimerEndsAt)
        XCTAssertFalse(vm.isSleepTimerActive)
    }

    func testCancelSleepTimerClearsState() {
        vm.startSleepTimer(minutes: 15)
        XCTAssertNotNil(vm.sleepTimerEndsAt)
        vm.cancelSleepTimer()
        XCTAssertNil(vm.sleepTimerEndsAt)
        XCTAssertFalse(vm.sleepAtEndOfTrack)
        XCTAssertFalse(vm.isSleepTimerActive)
    }

    func testEndOfTrackFlag() {
        vm.setSleepAtEndOfTrack(true)
        XCTAssertTrue(vm.sleepAtEndOfTrack)
        XCTAssertTrue(vm.isSleepTimerActive)
        XCTAssertNil(vm.sleepTimerEndsAt,
                     "End-of-track mode does not set a wall-clock end time.")
    }

    func testStartingCountdownCancelsEndOfTrack() {
        vm.setSleepAtEndOfTrack(true)
        vm.startSleepTimer(minutes: 10)
        XCTAssertFalse(vm.sleepAtEndOfTrack,
                       "Starting a countdown must replace end-of-track mode.")
        XCTAssertNotNil(vm.sleepTimerEndsAt)
    }

    func testEndOfTrackCancelsCountdown() {
        vm.startSleepTimer(minutes: 10)
        XCTAssertNotNil(vm.sleepTimerEndsAt)
        vm.setSleepAtEndOfTrack(true)
        XCTAssertNil(vm.sleepTimerEndsAt,
                     "Switching to end-of-track mode must cancel the countdown.")
        XCTAssertTrue(vm.sleepAtEndOfTrack)
    }

    func testStartingSecondTimerReplacesFirst() {
        vm.startSleepTimer(minutes: 5)
        let first = vm.sleepTimerEndsAt!
        // Re-start with a longer duration.
        vm.startSleepTimer(minutes: 30)
        let second = vm.sleepTimerEndsAt!
        XCTAssertGreaterThan(second.timeIntervalSince(first), 60,
                             "Restarting the timer must update the end time, not stack timers.")
    }
}
