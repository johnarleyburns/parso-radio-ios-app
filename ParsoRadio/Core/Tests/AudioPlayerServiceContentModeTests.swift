import XCTest
import MediaPlayer
@testable import ParsoMusic

@MainActor
final class AudioPlayerServiceContentModeTests: XCTestCase {

    func testDefaultIsMusicMode() {
        let svc = AudioPlayerService()
        XCTAssertEqual(svc.contentMode, .music)
        let center = MPRemoteCommandCenter.shared()
        XCTAssertTrue(center.nextTrackCommand.isEnabled)
        XCTAssertTrue(center.previousTrackCommand.isEnabled)
        XCTAssertFalse(center.skipBackwardCommand.isEnabled)
        XCTAssertFalse(center.skipForwardCommand.isEnabled)
    }

    func testSpokenWordModeEnablesTimeSkipAndDisablesTrackSkip() {
        let svc = AudioPlayerService()
        svc.setContentMode(.spokenWord)
        XCTAssertEqual(svc.contentMode, .spokenWord)
        let center = MPRemoteCommandCenter.shared()
        XCTAssertTrue(center.skipBackwardCommand.isEnabled,
                      "Spoken-word mode must enable lock-screen skip-back-15.")
        XCTAssertTrue(center.skipForwardCommand.isEnabled,
                      "Spoken-word mode must enable lock-screen skip-forward-15.")
        XCTAssertFalse(center.nextTrackCommand.isEnabled,
                       "Spoken-word mode must disable lock-screen next-track.")
        XCTAssertFalse(center.previousTrackCommand.isEnabled)
    }

    func testSkipIntervalsPreferred15s() {
        _ = AudioPlayerService()      // installs targets
        let center = MPRemoteCommandCenter.shared()
        XCTAssertEqual(center.skipBackwardCommand.preferredIntervals.map { $0.doubleValue },
                       [AudioPlayerService.skipInterval])
        XCTAssertEqual(center.skipForwardCommand.preferredIntervals.map { $0.doubleValue },
                       [AudioPlayerService.skipInterval])
    }

    func testToggleBetweenModes() {
        let svc = AudioPlayerService()
        svc.setContentMode(.spokenWord)
        svc.setContentMode(.music)
        let center = MPRemoteCommandCenter.shared()
        XCTAssertTrue(center.nextTrackCommand.isEnabled)
        XCTAssertTrue(center.previousTrackCommand.isEnabled)
        XCTAssertFalse(center.skipBackwardCommand.isEnabled)
        XCTAssertFalse(center.skipForwardCommand.isEnabled)
    }
}

@MainActor
final class PlayerViewModelContentModeTests: XCTestCase {

    func testLoadingSpokenWordChannelSetsSpokenMode() async throws {
        let db = try DatabaseService(path: ":memory:")
        let audio = AudioPlayerService()
        let vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: audio,
            downloadManager: DownloadManager(db: db)
        )
        // Pick a spoken-word channel from the registry (Lectures / Audiobooks / News).
        guard let spoken = Channel.defaults.first(where: { $0.contentType == .spokenWord }) else {
            XCTFail("No spoken-word channel in registry"); return
        }
        let loadTask = Task { await vm.load(channel: spoken) }
        await Task.yield()
        XCTAssertEqual(audio.contentMode, .spokenWord)
        loadTask.cancel()
    }

    func testLoadingMusicChannelSetsMusicMode() async throws {
        let db = try DatabaseService(path: ":memory:")
        let audio = AudioPlayerService()
        let vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: audio,
            downloadManager: DownloadManager(db: db)
        )
        // Use a Curated music channel.
        guard let music = Channel.defaults.first(where: { $0.contentType == .music }) else {
            XCTFail("No music channel in registry"); return
        }
        // Pre-set to spoken so we can observe the change.
        audio.setContentMode(.spokenWord)
        let loadTask = Task { await vm.load(channel: music) }
        await Task.yield()
        XCTAssertEqual(audio.contentMode, .music)
        loadTask.cancel()
    }
}
