import XCTest
@testable import ParsoMusic

/// Regression net for the playback invariants in PLAYBACK-TESTING-PLAN.md, driven
/// by the deterministic FakeAudioEngine. These use a PLAYLIST context because
/// playlist load/resume is entirely DB-backed (no network), so the tests are
/// fast and hermetic. Timeouts are injected at millisecond scale.
@MainActor
final class PlaybackReliabilityTests: XCTestCase {
    private var db: DatabaseService!
    private var engine: FakeAudioEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        engine = FakeAudioEngine()
        for k in ["session.kind", "session.contextId", "session.trackId",
                  "session.position", "lastChannelId"] {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    // Build a VM wired to the fake engine with explicit (tiny) timeouts. A LARGE
    // stallTimeout is used by tests that drive playback by hand so the watchdog
    // doesn't race their ticks; the stall test passes a tiny one on purpose.
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
        let pl = try await db.createPlaylist(name: "Reliability \(UUID())")
        for t in tracks { await db.addTrack(t, toPlaylist: pl.id) }
        return pl
    }

    // Yield the main actor + a short real pause so fire-and-forget Tasks and DB
    // continuations settle before we assert.
    private func settle(_ ms: UInt64 = 40) async {
        for _ in 0..<6 { await Task.yield() }
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
        for _ in 0..<6 { await Task.yield() }
    }

    // I4 — on a background-kill relaunch the DB position write can be lost; the
    // durable UserDefaults session offset must win over the stale DB row.
    func test_restorePlaylist_durableSessionOffsetBeatsStaleDBPosition() async throws {
        let vm = makeVM()
        let pl = try await seedPlaylist(["d1", "d2"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        // DB holds an OLD offset (the lost write); UserDefaults holds the truth.
        await db.savePosition(channelId: PlayerViewModel.playlistKey(pl.id),
                              trackId: order[0].id, seconds: 40)
        let d = UserDefaults.standard
        d.set("playlist", forKey: "session.kind")
        d.set(pl.id, forKey: "session.contextId")
        d.set(order[0].id, forKey: "session.trackId")
        d.set(137.0, forKey: "session.position")

        await vm.restoreLastSession(fallbackChannel: Channel.fmaJazzTestChannel,
                                    autoPlay: false)
        await settle()

        XCTAssertEqual(vm.currentTrack?.id, order[0].id)
        XCTAssertEqual(vm.currentPosition, 137, accuracy: 2.0,
            "durable session offset must beat the stale DB position on restore")
    }

    // I4 — when DB and durable offsets agree, restore lands exactly there (no
    // spurious reconcile).
    func test_restorePlaylist_matchingOffsets_resumeIsStable() async throws {
        let vm = makeVM()
        let pl = try await seedPlaylist(["m1", "m2"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        await db.savePosition(channelId: PlayerViewModel.playlistKey(pl.id),
                              trackId: order[1].id, seconds: 88)
        let d = UserDefaults.standard
        d.set("playlist", forKey: "session.kind")
        d.set(pl.id, forKey: "session.contextId")
        d.set(order[1].id, forKey: "session.trackId")
        d.set(88.0, forKey: "session.position")

        await vm.restoreLastSession(fallbackChannel: Channel.fmaJazzTestChannel,
                                    autoPlay: false)
        await settle()

        XCTAssertEqual(vm.currentTrack?.id, order[1].id)
        XCTAssertEqual(vm.currentPosition, 88, accuracy: 2.0)
    }

    // I2 — a track that never produces audio must be skipped within stallTimeout,
    // never buffer forever.
    func test_stalledTrackSkipsToNextWithinStallTimeout() async throws {
        let vm = makeVM(stallTimeout: 0.05)
        let pl = try await seedPlaylist(["s1", "s2"])
        await vm.loadPlaylist(pl)            // plays first track; fake never readies

        // The fake NEVER fires onReady/onTimeUpdate, so every loaded track
        // stalls. The watchdog must keep advancing (skip) rather than hang
        // forever — so MORE than the single initial load occurs, then it stops
        // (give-up cap). We don't assert the first track stays loaded: with a
        // 50 ms stallTimeout the watchdog may already have skipped it.
        try await Task.sleep(nanoseconds: 400_000_000)
        await settle()

        XCTAssertGreaterThan(engine.playCount, 1,
            "a track that never produces audio must be skipped within stallTimeout, never hang")
    }

    // I3 — the persisted playlist offset reflects the last observed position, not
    // 0 and not a stale value.
    func test_savepointReflectsLastObservedPosition() async throws {
        let vm = makeVM()
        let pl = try await seedPlaylist(["p1"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        await vm.loadPlaylist(pl)
        await settle()
        engine.completeReady(duration: 300)
        engine.emitTick(10)
        engine.emitTick(20)
        await settle()
        vm.saveCurrentSpot()
        await settle(80)

        let saved = await db.loadPosition(channelId: PlayerViewModel.playlistKey(pl.id))
        XCTAssertEqual(saved?.trackId, order[0].id)
        XCTAssertEqual(saved?.seconds ?? -1, 20, accuracy: 2.0,
            "saved offset must reflect the last tick, never reset to 0")
    }

    // I1 — once audio is genuinely progressing the loading spinner is cleared.
    func test_firstTickClearsLoadingSpinner() async throws {
        let vm = makeVM()
        let pl = try await seedPlaylist(["l1"])
        await vm.loadPlaylist(pl)
        await settle()
        XCTAssertTrue(vm.isLoading, "spinner shows until audio starts")
        engine.completeReady(duration: 300)
        engine.emitTick(2)
        await settle()
        XCTAssertFalse(vm.isLoading, "spinner clears once a real time tick arrives")
        XCTAssertNotNil(vm.currentTrack)
    }
}
