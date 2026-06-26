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

    private func makeMissingLocalTrack(_ id: String) -> Track {
        let path = "/private/tmp/lorewave-missing-\(id)-\(UUID().uuidString).mp3"
        return Track(id: id, source: "local", title: "Missing \(id)", artist: "A",
                     duration: 300,
                     streamURL: URL(fileURLWithPath: path),
                     downloadURL: nil, localFilePath: path,
                     license: .cc0, tags: [],
                     qualityScore: 0.8, rawCreator: "", composer: nil,
                     instruments: [], metadataConfidence: 2.0,
                     isLocal: true)
    }

    private func makeBookChapter(_ parent: String, part: Int) -> Track {
        var track = Track.makeStub(id: "\(parent)/chapter-\(part).mp3",
                                   title: "Chapter \(part)",
                                   parentIdentifier: parent)
        track.partNumber = part
        track.totalParts = 2
        return track
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

    // Tapping a track in a playlist must start playback from that track.
    // Regression: PlaylistPlaybackController.loadPlaylist was calling
    // beginTransition (which calls audioPlayer.skip()) before playTrack,
    // causing a double-teardown that prevented audio from starting.
    func test_tappingPlaylistTrack_playsFromTappedTrack() async throws {
        let vm = makeVM()
        let pl = try await seedPlaylist(["ta", "tb", "tc"])
        let tracks = await db.fetchTracks(forPlaylist: pl.id)
        // Tap the second track
        await vm.loadPlaylist(pl, startingAt: tracks[1])
        await settle()

        XCTAssertEqual(vm.currentTrack?.id, tracks[1].id,
            "startingAt: the tapped track must become currentTrack")
        XCTAssertEqual(vm.playlistIndex, 1,
            "playlistIndex must point to the tapped track")
        XCTAssertEqual(engine.playCount, 1,
            "exactly one play() invocation — no double-load from beginTransition + playTrack")
        XCTAssertEqual(engine.skipCount, 0,
            "no skip() should fire when loading a playlist")
    }

    // Start from the first track (no explicit startingAt) — same invariants.
    func test_loadingPlaylistWithoutStartingAt_playsFirstTrack() async throws {
        let vm = makeVM()
        let pl = try await seedPlaylist(["ta", "tb"])
        let tracks = await db.fetchTracks(forPlaylist: pl.id)
        await vm.loadPlaylist(pl)
        await settle()

        XCTAssertEqual(vm.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(vm.playlistIndex, 0)
        XCTAssertEqual(engine.playCount, 1)
        XCTAssertEqual(engine.skipCount, 0)
    }

    func test_musicForYouThenJumpBackInStopsOutgoingAudioWhenNewTrackCannotLoad() async throws {
        let vm = makeVM()
        let musicForYou = makeFMATrack("mfy-current")
        await vm.playRecentTrack(musicForYou)
        await settle()
        XCTAssertEqual(engine.liveTrack?.id, musicForYou.id)
        engine.completeReady(duration: 300)
        engine.emitTick(12)
        await settle()

        let skipCountBeforeSwitch = engine.skipCount
        let jumpBackIn = makeMissingLocalTrack("jbi-missing")
        await vm.playRecentTrack(jumpBackIn)
        await settle()

        XCTAssertGreaterThan(engine.skipCount, skipCountBeforeSwitch,
            "Jump Back In must tear down outgoing recommendation audio before resolving the tapped track.")
        XCTAssertNil(engine.liveTrack,
            "The old Music For You engine item must not keep playing if the Jump Back In track fails before play().")
        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(vm.isPlaying)
    }

    func test_jumpBackInMusicClearsStalePlaylistContextBeforePlayingTrack() async throws {
        let vm = makeVM()
        let stalePlaylist = try await seedPlaylist(["stale-a", "stale-b"])
        vm.currentPlaylist = stalePlaylist
        vm.playlistTracks = await db.fetchTracks(forPlaylist: stalePlaylist.id)
        vm.playlistIndex = 1

        let jumpBackIn = makeFMATrack("jbi-track")
        await vm.playRecentTrack(jumpBackIn)
        await settle()

        XCTAssertNil(vm.currentPlaylist,
            "A single Jump Back In music track must not inherit an old playlist/album context.")
        XCTAssertTrue(vm.playlistTracks.isEmpty)
        XCTAssertEqual(vm.playlistIndex, 0)
        XCTAssertEqual(vm.currentPlaybackContext?.origin, .recentlyPlayed)
        XCTAssertEqual(engine.liveTrack?.id, jumpBackIn.id)
    }

    func test_booksForYouWholeWorkSwitchStopsOutgoingTrackBeforeAlbumPlayback() async throws {
        let vm = makeVM()
        let oldTrack = makeFMATrack("old-music")
        await vm.playRecentTrack(oldTrack)
        await settle()
        XCTAssertEqual(engine.liveTrack?.id, oldTrack.id)
        let skipCountBeforeSwitch = engine.skipCount

        let chapters = [makeBookChapter("book-a", part: 1),
                        makeBookChapter("book-a", part: 2)]
        await vm.playAlbumTracks(chapters, title: "Book A",
                                 mediaKind: .audiobook, origin: .bookForYou)
        await settle()

        XCTAssertGreaterThan(engine.skipCount, skipCountBeforeSwitch,
            "Books For You / whole-work playback must stop outgoing audio before starting the album context.")
        XCTAssertEqual(engine.liveTrack?.id, chapters[0].id)
        XCTAssertEqual(vm.currentPlaylist?.id, "album:book-a")
        XCTAssertEqual(vm.activeMediaKind, .audiobook)
    }
}
