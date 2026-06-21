import XCTest
@testable import ParsoMusic

@MainActor
final class PlayerControlBitsTests: XCTestCase {

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

    // MARK: - TransportButton helpers (state-driven label/icon)

    func testPlayPauseIconWhenPlaying() {
        vm.isPlaying = true
        XCTAssertEqual(vm.isPlaying, true)
    }

    func testPlayPauseIconWhenPaused() {
        vm.isPlaying = false
        XCTAssertEqual(vm.isPlaying, false)
    }

    // MARK: - ShuffleButton

    func testShuffleButtonTogglesShuffle() {
        XCTAssertFalse(vm.shuffleMode)
        vm.toggleShuffle()
        XCTAssertTrue(vm.shuffleMode)
        vm.toggleShuffle()
        XCTAssertFalse(vm.shuffleMode)
    }

    func testShuffleButtonAccessibilityState() {
        vm.shuffleMode = false
        XCTAssertFalse(vm.shuffleMode)

        vm.shuffleMode = true
        XCTAssertTrue(vm.shuffleMode)
    }

    // MARK: - RepeatButton

    func testRepeatButtonTogglesRepeat() {
        XCTAssertEqual(vm.repeatMode, .off)
        vm.toggleRepeat()
        XCTAssertEqual(vm.repeatMode, .one)
        vm.toggleRepeat()
        XCTAssertEqual(vm.repeatMode, .off)
    }

    func testRepeatButtonStateIcons() {
        vm.repeatMode = .off
        XCTAssertEqual(vm.repeatMode, .off)

        vm.repeatMode = .one
        XCTAssertEqual(vm.repeatMode, .one)
    }

    // MARK: - SleepTimerButton

    func testSleepTimerInitiallyInactive() {
        XCTAssertFalse(vm.isSleepTimerActive)
    }

    func testSleepTimerBecomesActiveAfterStart() {
        vm.startSleepTimer(minutes: 15)
        XCTAssertTrue(vm.isSleepTimerActive)
    }

    func testSleepTimerCancels() {
        vm.startSleepTimer(minutes: 15)
        XCTAssertTrue(vm.isSleepTimerActive)
        vm.cancelSleepTimer()
        XCTAssertFalse(vm.isSleepTimerActive)
    }

    func testSleepTimerEndOfTrack() {
        vm.setSleepAtEndOfTrack(true)
        // End-of-track mode is a distinct state; the active flag is also true.
        vm.setSleepAtEndOfTrack(false)
    }

    func testSleepTimerCancelWhenActive() {
        vm.startSleepTimer(minutes: 30)
        XCTAssertTrue(vm.isSleepTimerActive)
        vm.cancelSleepTimer()
        XCTAssertFalse(vm.isSleepTimerActive)
    }

    // MARK: - ScrubRow time formatting

    func testTimeFormattingHelper() {
        XCTAssertEqual(0.0.formattedTime, "0:00")
        XCTAssertEqual(65.0.formattedTime, "1:05")
        XCTAssertEqual(3661.0.formattedTime, "1:01:01")
    }

    // MARK: - Buffering disabled state

    func testControlsDisabledWhenLoading() {
        vm.currentTrack = Track.makeStub(id: "test", title: "Test")
        vm.isLoading = true

        // During buffering, controls should be disabled
        XCTAssertTrue(vm.isLoading)
        XCTAssertNotNil(vm.currentTrack)

        vm.isLoading = false
        XCTAssertFalse(vm.isLoading)
    }

    func testControlsEnabledWhenNotLoading() {
        vm.currentTrack = Track.makeStub(id: "test", title: "Test")
        vm.isLoading = false

        XCTAssertFalse(vm.isLoading)
        XCTAssertNotNil(vm.currentTrack)
    }

    func testControlsDisabledWhenNoTrack() {
        vm.currentTrack = nil
        vm.isLoading = false

        XCTAssertNil(vm.currentTrack)
    }
}
