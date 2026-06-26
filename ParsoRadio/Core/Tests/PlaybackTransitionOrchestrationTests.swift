import XCTest
@testable import ParsoMusic

/// Verifies the transition policy is actually threaded through `PlayerViewModel`
/// to the engine — driven by the deterministic `FakeAudioEngine`, playlist
/// context (DB-backed, no network) for hermetic, instant tests.
@MainActor
final class PlaybackTransitionOrchestrationTests: XCTestCase {
    private var db: DatabaseService!
    private var engine: FakeAudioEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        engine = FakeAudioEngine()
        for k in ["session.kind", "session.contextId", "session.trackId",
                  "session.position", "lastChannelId", "musicCrossfadeEnabled"] {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    private func makeVM(stallTimeout: Double = 5.0) -> PlayerViewModel {
        PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: engine,
            downloadManager: DownloadManager(db: db),
            loadTimeout: 0.05,
            stallTimeout: stallTimeout
        )
    }

    private func makeFMATrack(_ id: String) -> Track {
        Track(id: id, source: "fma", title: "T \(id)", artist: "A",
              duration: 300,
              streamURL: URL(string: "https://freemusicarchive.org/\(id)")!,
              downloadURL: nil, localFilePath: nil, license: .cc0, tags: ["jazz"],
              qualityScore: 0.8, rawCreator: "", composer: nil, instruments: [],
              metadataConfidence: 2.0)
    }

    private func seedPlaylist(_ ids: [String]) async throws -> Playlist {
        let tracks = ids.map(makeFMATrack)
        await db.saveTracks(tracks)
        let pl = try await db.createPlaylist(name: "Transitions \(UUID())")
        for t in tracks { await db.addTrack(t, toPlaylist: pl.id) }
        return pl
    }

    private func settle(_ ms: UInt64 = 40) async {
        for _ in 0..<6 { await Task.yield() }
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
        for _ in 0..<6 { await Task.yield() }
    }

    // Loading a playlist must pass a play transition (music context switch =
    // fadeOutIn) and must NOT skip first (the double-teardown regression).
    func test_loadPlaylist_passesPlayTransition_noSkip() async throws {
        let vm = makeVM()
        let pl = try await seedPlaylist(["a1", "a2"])
        await vm.loadPlaylist(pl)
        await settle()

        XCTAssertEqual(engine.skipCount, 0, "loading a playlist must not skip (no double-teardown)")
        XCTAssertEqual(engine.playCount, 1)
        XCTAssertEqual(engine.lastPlayTransition, .fadeOutIn(out: 0.30, in: 0.25),
            "music playlist load should fade out/in, not hard-cut")
    }

    // Manual next on a music track must fade out the outgoing track (explicit
    // user switch), never an immediate hard stop.
    func test_musicManualNext_passesFadeOutSkip() async throws {
        let vm = makeVM()
        let pl = try await seedPlaylist(["m1", "m2", "m3"])
        await vm.loadPlaylist(pl)
        await settle()
        engine.completeReady(duration: 300)
        engine.emitTick(2)
        await settle()

        vm.skip()
        await settle()

        XCTAssertEqual(engine.lastSkipTransition, .fadeOutIn(out: 0.25, in: 0.25),
            "music manual next must fade the outgoing track, not hard-stop")
        XCTAssertNotEqual(engine.lastSkipTransition, .immediate)
    }

    // The sleep-timer fade seam: fadeOutThenPause is recorded and stops playback.
    func test_fakeEngine_recordsSleepFadeOutThenPause() {
        engine.completeReady(duration: 100)
        engine.fadeOutThenPause(duration: 8)
        XCTAssertEqual(engine.fadeOutPauseCount, 1)
        XCTAssertEqual(engine.lastFadeOutPauseDuration, 8)
        XCTAssertFalse(engine.isPlaying)
    }

    // Phase 2: a music-channel track arms the engine to fire natural advance a
    // crossfade-length early (so its tail can overlap the next track).
    func test_musicChannel_armsCrossfadeWhenEnabled() async {
        UserDefaults.standard.set(true, forKey: "musicCrossfadeEnabled")
        let vm = makeVM()
        vm.currentChannel = Channel.fmaJazzTestChannel
        await db.saveTracks([makeFMATrack("c1")])
        await vm.playTrack(makeFMATrack("c1"), seekTo: nil, reason: .channelChange)
        await settle()
        XCTAssertEqual(engine.crossfadeArmCount, 1, "music-channel play must arm the crossfade")
        XCTAssertEqual(engine.lastCrossfadeLead, 2.0)
        UserDefaults.standard.removeObject(forKey: "musicCrossfadeEnabled")
    }

    // With the setting off, music-channel plays never arm the crossfade.
    func test_musicChannel_doesNotArmWhenDisabled() async {
        UserDefaults.standard.set(false, forKey: "musicCrossfadeEnabled")
        let vm = makeVM()
        vm.currentChannel = Channel.fmaJazzTestChannel
        await db.saveTracks([makeFMATrack("c2")])
        await vm.playTrack(makeFMATrack("c2"), seekTo: nil, reason: .channelChange)
        await settle()
        XCTAssertEqual(engine.crossfadeArmCount, 0, "crossfade disabled must not arm")
        UserDefaults.standard.removeObject(forKey: "musicCrossfadeEnabled")
    }

    // Playlists keep the Phase 1 fade-in (no overlap), so they never arm.
    func test_playlistContext_doesNotArmCrossfade() async throws {
        UserDefaults.standard.set(true, forKey: "musicCrossfadeEnabled")
        let vm = makeVM()
        let pl = try await seedPlaylist(["x1", "x2"])
        await vm.loadPlaylist(pl)
        await settle()
        XCTAssertEqual(engine.crossfadeArmCount, 0, "playlist context must not arm music crossfade")
        UserDefaults.standard.removeObject(forKey: "musicCrossfadeEnabled")
    }
}
