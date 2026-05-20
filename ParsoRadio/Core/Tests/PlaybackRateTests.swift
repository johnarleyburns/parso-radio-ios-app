import XCTest
@testable import ParsoMusic

@MainActor
final class PlaybackRateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "playbackRate")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "playbackRate")
        super.tearDown()
    }

    func testDefaultRateIsOne() {
        let svc = AudioPlayerService()
        XCTAssertEqual(svc.playbackRate, 1.0, accuracy: 0.001,
                       "Fresh AudioPlayerService should default to 1× playback.")
    }

    func testClampLowerBound() {
        XCTAssertEqual(AudioPlayerService.clampRate(0.0),   0.5)
        XCTAssertEqual(AudioPlayerService.clampRate(0.25),  0.5)
        XCTAssertEqual(AudioPlayerService.clampRate(0.5),   0.5)
        XCTAssertEqual(AudioPlayerService.clampRate(-1.0),  0.5)
    }

    func testClampUpperBound() {
        XCTAssertEqual(AudioPlayerService.clampRate(2.0),  2.0)
        XCTAssertEqual(AudioPlayerService.clampRate(2.5),  2.0)
        XCTAssertEqual(AudioPlayerService.clampRate(99.0), 2.0)
    }

    func testClampPassesValuesInRange() {
        for r: Float in [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0] {
            XCTAssertEqual(AudioPlayerService.clampRate(r), r, accuracy: 0.0001)
        }
    }

    func testSetPlaybackRatePersistsAndIsRestored() {
        let svc1 = AudioPlayerService()
        svc1.setPlaybackRate(1.5)
        XCTAssertEqual(svc1.playbackRate, 1.5, accuracy: 0.001)

        // A fresh service in the same process reads the persisted value.
        let svc2 = AudioPlayerService()
        XCTAssertEqual(svc2.playbackRate, 1.5, accuracy: 0.001,
                       "Rate must persist across AudioPlayerService instances via UserDefaults.")
    }

    func testSetPlaybackRateClampsOutOfRange() {
        let svc = AudioPlayerService()
        svc.setPlaybackRate(0.1)
        XCTAssertEqual(svc.playbackRate, 0.5, accuracy: 0.001)
        svc.setPlaybackRate(5.0)
        XCTAssertEqual(svc.playbackRate, 2.0, accuracy: 0.001)
    }

    func testPlayerViewModelMirrorsAudioPlayerRate() throws {
        let db = try DatabaseService(path: ":memory:")
        let audio = AudioPlayerService()
        audio.setPlaybackRate(1.25)
        let vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: audio,
            downloadManager: DownloadManager(db: db)
        )
        XCTAssertEqual(vm.playbackRate, 1.25, accuracy: 0.001,
                       "PlayerViewModel.playbackRate must initialise from the audio player's rate.")
        vm.setPlaybackRate(1.75)
        XCTAssertEqual(vm.playbackRate, 1.75, accuracy: 0.001)
        XCTAssertEqual(audio.playbackRate, 1.75, accuracy: 0.001,
                       "VM setter must update the underlying AudioPlayerService rate.")
    }

    func testPlaybackRateOptionsAreOrderedAndCoverDoublings() {
        let opts = PlayerViewModel.playbackRateOptions
        XCTAssertEqual(opts.first, 0.5)
        XCTAssertEqual(opts.last,  2.0)
        XCTAssertEqual(opts.sorted(), opts, "Speed options must be ascending.")
        XCTAssertTrue(opts.contains(1.0), "1× must always be an option.")
    }
}
