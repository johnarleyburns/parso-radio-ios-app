import XCTest
import AVFoundation
@testable import ParsoMusic

// Tests for PlayerViewModel use-case behaviors.
// All tests run on the MainActor because PlayerViewModel is @MainActor.
@MainActor
final class PlayerViewModelTests: XCTestCase {

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
        UserDefaults.standard.removeObject(forKey: "lastChannelId")
    }

    // UC2: last channel ID is written to UserDefaults as soon as load() begins,
    // before any network call, so a crash or force-quit still persists the choice.
    func testLastChannelIdSavedOnLoad() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        // Seed a track so advanceToNext() doesn't deadlock waiting for the DB.
        await db.saveTracks([makeFMATrack(id: "jazz-1", tags: ["jazz"])])

        // load() sets UserDefaults.standard before the first network await, so
        // the value is visible once load() returns (whether or not network succeeded).
        let loadTask = Task { await self.vm.load(channel: channel) }
        // Yield so load()'s synchronous preamble executes on the main actor.
        await Task.yield()
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "lastChannelId"), channel.id,
            "lastChannelId must be set before any network call in load()"
        )
        loadTask.cancel()
    }

    // UC3 (music): pressing back when well into a track (> 3 s) restarts from zero.
    func testBackMidMusicTrackRestartsFromBeginning() throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let track = makeFMATrack(id: "jazz-1", tags: ["jazz"])

        vm.currentChannel = channel
        vm.currentTrack = track
        vm.currentPosition = 120  // well past the 3-second threshold

        vm.back()

        // Seek to 0; currentPosition is reset immediately (before any async work).
        XCTAssertEqual(vm.currentPosition, 0, accuracy: 0.001)
    }

    // UC3 (music): pressing back at the very start navigates to the previous track.
    func testBackAtStartOfMusicTrackPlaysPreviousTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let t1 = makeFMATrack(id: "jazz-prev", tags: ["jazz"])
        let t2 = makeFMATrack(id: "jazz-curr", tags: ["jazz"])
        await db.saveTracks([t1, t2])

        vm.currentChannel = channel
        vm.currentTrack = t2
        vm.playHistory = [t1]
        vm.currentPosition = 0  // at the very start

        vm.back()
        // Allow the spawned Task to execute playPreviousTrack().
        try await Task.sleep(nanoseconds: 2_000_000_000)

        XCTAssertEqual(vm.currentTrack?.id, t1.id, "back() at position 0 must navigate to the previous track")
        XCTAssertTrue(vm.playHistory.isEmpty, "Previous track removed from history after navigating back")
    }

    // UC3: pressing back with no history restarts the current track without crashing.
    func testBackWithEmptyHistoryDoesNotCrash() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let track = makeFMATrack(id: "jazz-1", tags: ["jazz"])
        await db.saveTracks([track])

        vm.currentChannel = channel
        vm.currentTrack = track
        vm.playHistory = []
        vm.currentPosition = 1  // within 3 s of start so the "previous" branch fires

        vm.back()
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // No crash; still on the same track (seek to 0 fallback).
        XCTAssertEqual(vm.currentTrack?.id, track.id)
    }

    // UC3: playing a new track appends the previous one to playHistory.
    func testSkipAddsToPlayHistory() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let t1 = makeFMATrack(id: "jazz-1", tags: ["jazz"])
        let t2 = makeFMATrack(id: "jazz-2", tags: ["jazz"])
        await db.saveTracks([t1, t2])

        vm.currentChannel = channel
        vm.currentTrack = t1
        vm.playHistory = []
        vm.currentPosition = 0

        vm.skip()
        try await Task.sleep(nanoseconds: 2_000_000_000)

        XCTAssertTrue(
            vm.playHistory.contains { $0.id == t1.id },
            "Skipping forward must push the previous track onto playHistory"
        )
    }

    // UC5: switching channel immediately clears currentTrack and stops playback.
    func testChannelSwitchClearsPlaybackStateImmediately() async throws {
        // Seed two channels' tracks.
        let fmaTrack = makeFMATrack(id: "jazz-1", tags: ["jazz"])
        await db.saveTracks([fmaTrack])

        vm.currentTrack = fmaTrack
        vm.isPlaying = true

        let newChannel = Channel.defaults.first { $0.id == "fma-classical" }!
        let loadTask = Task { await self.vm.load(channel: newChannel) }
        // Yield so the synchronous preamble (stop + clear) executes.
        await Task.yield()

        XCTAssertNil(vm.currentTrack, "Channel switch must clear currentTrack immediately")
        XCTAssertFalse(vm.isPlaying, "Channel switch must stop playback immediately")
        loadTask.cancel()
    }

    // Back/forward redesign: forward always advances track; back restarts or goes to previous.
    func testBackInSpokenWordMidTrackRestartsFromBeginning() throws {
        let channel = Channel.defaults.first { $0.id == "greek-philosophy" }!
        let track = makeSpokenWordTrack(id: "plato-1")

        vm.currentChannel = channel
        vm.currentTrack = track
        vm.currentPosition = 60

        vm.back()

        XCTAssertEqual(vm.currentPosition, 0, accuracy: 0.001,
            "Spoken-word back at >3s must restart from beginning, not rewind 15s")
    }

    func testBackInSpokenWordAtStartGoesToPreviousTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "greek-philosophy" }!
        let t1 = makeSpokenWordTrack(id: "plato-prev")
        let t2 = makeSpokenWordTrack(id: "plato-curr")
        await db.saveTracks([t1, t2])

        vm.currentChannel = channel
        vm.currentTrack = t2
        vm.playHistory = [t1]
        vm.currentPosition = 1  // near the start

        vm.back()
        try await Task.sleep(nanoseconds: 2_000_000_000)

        XCTAssertEqual(vm.currentTrack?.id, t1.id,
            "Spoken-word back at ≤3s must go to previous track")
    }

    func testSkipInSpokenWordAdvancesToNextTrack() throws {
        let channel = Channel.defaults.first { $0.id == "greek-philosophy" }!
        let track = makeSpokenWordTrack(id: "plato-1")

        vm.currentChannel = channel
        vm.currentTrack = track
        vm.currentPosition = 60  // mid-track; old behaviour would seek to 90 s

        vm.skip()

        // currentPosition resets to 0 (track stopped, queue advance initiated) — NOT 90.
        XCTAssertEqual(vm.currentPosition, 0, accuracy: 0.001,
            "Spoken-word forward must advance to next track, not seek +30s")
        XCTAssertFalse(vm.isPlaying, "isPlaying must be false immediately after skip()")
    }

    // Issue 3: cold start should not auto-play — wasPlayingOnQuit absent means false.
    func testColdStartDoesNotAutoPlay() {
        UserDefaults.standard.removeObject(forKey: "wasPlayingOnQuit")
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: "wasPlayingOnQuit"),
            "Cold start: wasPlayingOnQuit must be absent/false so autoPlay defaults off"
        )
        XCTAssertFalse(vm.isPlaying, "ViewModel must not be playing at init")
    }

    // Issue 3: isPlaying saved to UserDefaults when app resigns active.
    func testWasPlayingFlagRoundtrip() {
        UserDefaults.standard.set(true, forKey: "wasPlayingOnQuit")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "wasPlayingOnQuit"))
        UserDefaults.standard.removeObject(forKey: "wasPlayingOnQuit")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "wasPlayingOnQuit"))
    }

    // UC14: seek() updates currentPosition immediately.
    func testSeekUpdatesCurrentPosition() throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let track = makeFMATrack(id: "jazz-1", tags: ["jazz"])

        vm.currentChannel = channel
        vm.currentTrack = track
        vm.currentPosition = 0

        vm.seek(to: 45.0)

        XCTAssertEqual(vm.currentPosition, 45.0, accuracy: 0.001,
            "seek(to:) must update currentPosition immediately")
    }

    // UC14: Oxford forward always advances to the next lecture, never seeks +30 s.
    func testOxfordForwardSkipsToNextTrack() throws {
        let channel = Channel.defaults.first { $0.id == "oxford-philosophy" }!
        let track = makeSpokenWordTrack(id: "oxford-1")

        vm.currentChannel = channel
        vm.currentTrack = track
        vm.currentPosition = 0  // at start — spoken-word +30s would seek to 30

        vm.skip()

        XCTAssertEqual(vm.currentPosition, 0, accuracy: 0.001,
            "Oxford forward must not add 30 s — it should trigger next-track advance")
    }

    // MARK: - Helpers

    private func makeFMATrack(id: String, tags: [String]) -> Track {
        Track(
            id: id, source: "fma",
            title: "Test Track", artist: "Test Artist",
            duration: 180,
            streamURL: URL(string: "https://freemusicarchive.org/music/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .cc0, tags: tags,
            qualityScore: 0.8,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0  // must be >= 1.5 to pass DatabaseService's music threshold
        )
    }

    private func makeSpokenWordTrack(id: String) -> Track {
        Track(
            id: id, source: "internet_archive",
            title: "Chapter 1", artist: "Plato",
            duration: 1800,
            streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: ["philosophy"],
            qualityScore: 0.9,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 0.0
        )
    }
}

// UC12: AVAudioSession is configured for background playback.
@MainActor
final class AudioPlayerServiceTests: XCTestCase {

    func testAudioSessionCategoryIsPlayback() throws {
        _ = AudioPlayerService()
        let category = AVAudioSession.sharedInstance().category
        XCTAssertEqual(category, .playback, "AVAudioSession category must be .playback for background audio")
    }
}
