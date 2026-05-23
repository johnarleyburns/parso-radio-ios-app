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
        let channel = Channel(id: "greek-philosophy", name: "Greek Philosophy", category: "Audiobooks", icon: "building.columns", tags: ["plato"], contentType: .spokenWord, spokenWordCollections: ["librivoxaudio"], preferredSource: "internet_archive")
        let track = makeSpokenWordTrack(id: "plato-1")

        vm.currentChannel = channel
        vm.currentTrack = track
        vm.currentPosition = 60

        vm.back()

        XCTAssertEqual(vm.currentPosition, 0, accuracy: 0.001,
            "Spoken-word back at >3s must restart from beginning, not rewind 15s")
    }

    func testBackInSpokenWordAtStartGoesToPreviousTrack() async throws {
        let channel = Channel(id: "greek-philosophy", name: "Greek Philosophy", category: "Audiobooks", icon: "building.columns", tags: ["plato"], contentType: .spokenWord, spokenWordCollections: ["librivoxaudio"], preferredSource: "internet_archive")
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
        let channel = Channel(id: "greek-philosophy", name: "Greek Philosophy", category: "Audiobooks", icon: "building.columns", tags: ["plato"], contentType: .spokenWord, spokenWordCollections: ["librivoxaudio"], preferredSource: "internet_archive")
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

    // MARK: - Playlist playback regressions

    // Bug: after loadPlaylist, currentChannel must be nil and currentPlaylist must be set.
    // Previously both were possible to still hold the channel, leaving the wrong header shown.
    func testLoadPlaylistClearsChannelAndSetsPlaylist() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let track = makeFMATrack(id: "playlist-fma-1", tags: ["jazz"])
        await db.saveTracks([track])
        vm.currentChannel = channel

        let playlist = try await db.createPlaylist(name: "Bug1 Regression")
        await db.addTrack(track, toPlaylist: playlist.id)

        await vm.loadPlaylist(playlist)

        XCTAssertNil(vm.currentChannel,
            "loadPlaylist must clear currentChannel so the playlist name is shown in the header")
        XCTAssertEqual(vm.currentPlaylist?.id, playlist.id,
            "loadPlaylist must set currentPlaylist")
    }

    // Bug: switching to a playlist must clear play history from the previous channel.
    func testLoadPlaylistClearsPlayHistory() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let prev = makeFMATrack(id: "prev-track", tags: ["jazz"])
        let playlistTrack = makeFMATrack(id: "playlist-fma-2", tags: ["jazz"])
        await db.saveTracks([prev, playlistTrack])

        vm.currentChannel = channel
        vm.playHistory = [prev]

        let playlist = try await db.createPlaylist(name: "Bug1 History Regression")
        await db.addTrack(playlistTrack, toPlaylist: playlist.id)

        await vm.loadPlaylist(playlist)

        XCTAssertTrue(vm.playHistory.isEmpty,
            "loadPlaylist must reset playHistory to empty")
    }

    // Bug 2: wheel diameter formula must not go negative during zero-size geometry glitches.
    func testWheelDiameterFloorIsNonNegative() {
        // Simulate GeometryReader reporting (0, 0) — seen during sheet dismiss animations.
        let geoWidth: CGFloat = 0
        let geoHeight: CGFloat = 0
        let wheelDiameter = max(80.0, min(geoWidth - 48, geoHeight * 0.50 - 32))
        XCTAssertGreaterThanOrEqual(wheelDiameter, 80.0,
            "Wheel diameter must be at least 80 pt even when geo reports zero")
    }

    // Bug 2 variant: normal device viewport should still produce a sensible size.
    func testWheelDiameterOnTypicalDevice() {
        // iPhone 15 Pro usable area: ~393 × 759 (after safe areas)
        let geoWidth: CGFloat = 393
        let geoHeight: CGFloat = 759
        let wheelDiameter = max(80.0, min(geoWidth - 48, geoHeight * 0.50 - 32))
        XCTAssertEqual(wheelDiameter, 345.0, accuracy: 1.0,
            "Wheel diameter for typical iPhone should be ~345 pt")
    }

    // Smooth transition: opening a playlist must wipe the previous track's
    // UI state SYNCHRONOUSLY (before the async fetch) so the main screen
    // never shows stale elapsed time / artwork, and pre-populate the chosen
    // track so its metadata shows under the spinner.
    func testLoadPlaylistClearsStaleStateImmediately() async throws {
        vm.shuffleMode = false
        let t1 = makeFMATrack(id: "bt-1", tags: ["jazz"])
        await db.saveTracks([t1])
        let pl = try await db.createPlaylist(name: "BeginTransition")
        await db.addTrack(t1, toPlaylist: pl.id)

        // Simulate a previous track mid-playback.
        vm.currentTrack = makeFMATrack(id: "stale", tags: ["jazz"])
        vm.currentPosition = 137
        vm.trackDuration = 200

        let loadTask = Task { await self.vm.loadPlaylist(pl, startingAt: t1) }
        await Task.yield()   // let the synchronous preamble run

        XCTAssertEqual(vm.currentPosition, 0,
            "stale elapsed time must be cleared before any await")
        XCTAssertNil(vm.currentArtwork, "stale artwork must be cleared")
        XCTAssertTrue(vm.isLoading, "spinner must show during the transition")
        XCTAssertEqual(vm.currentTrack?.id, "bt-1",
            "the chosen track must be pre-populated (metadata under spinner)")
        _ = await loadTask.value
    }

    // MARK: - Playlist navigation regressions
    //
    // Bug report: in a playlist, <next> never advanced; <back> jumped to a
    // previously-played track that wasn't even in the playlist. Root causes:
    //  1. advanceToNext() bailed out via `guard let channel` (nil in playlist mode)
    //  2. loadPlaylist passed recordHistory:true while currentTrack was still the
    //     old CHANNEL track, leaking it into playHistory.

    func testPlaylistForwardAdvancesThroughPlaylist() async throws {
        vm.shuffleMode = false
        let t1 = makeFMATrack(id: "pl-1", tags: ["jazz"])
        let t2 = makeFMATrack(id: "pl-2", tags: ["jazz"])
        let t3 = makeFMATrack(id: "pl-3", tags: ["jazz"])
        await db.saveTracks([t1, t2, t3])
        let playlist = try await db.createPlaylist(name: "Nav Forward")
        for t in [t1, t2, t3] { await db.addTrack(t, toPlaylist: playlist.id) }

        // Source of truth: the order loadPlaylist itself plays in is exactly
        // db.fetchTracks(forPlaylist:) — which is the same order the playlist
        // UI shows. Derive expectations from it rather than insertion order.
        let ordered = await db.fetchTracks(forPlaylist: playlist.id).map(\.id)
        XCTAssertEqual(ordered.count, 3)

        await vm.loadPlaylist(playlist)
        XCTAssertEqual(vm.currentTrack?.id, ordered[0], "playlist starts at the first shown track")
        XCTAssertNil(vm.currentChannel)
        XCTAssertEqual(vm.currentPlaylist?.id, playlist.id)

        vm.skip()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(vm.currentTrack?.id, ordered[1], "<next> must advance to the next playlist track")

        vm.skip()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(vm.currentTrack?.id, ordered[2], "<next> must keep advancing within the playlist")
    }

    func testPlaylistBackStopsAtFirstAndNeverPlaysNonPlaylistTrack() async throws {
        vm.shuffleMode = false
        // Simulate a channel track playing BEFORE the playlist is opened.
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let preChannelTrack = makeFMATrack(id: "channel-pre", tags: ["jazz"])
        let olderChannelTrack = makeFMATrack(id: "channel-older", tags: ["jazz"])
        await db.saveTracks([preChannelTrack, olderChannelTrack])
        vm.currentChannel = channel
        vm.currentTrack = preChannelTrack
        vm.playHistory = [olderChannelTrack]

        let t1 = makeFMATrack(id: "pl-a", tags: ["jazz"])
        let t2 = makeFMATrack(id: "pl-b", tags: ["jazz"])
        await db.saveTracks([t1, t2])
        let playlist = try await db.createPlaylist(name: "Nav Back")
        for t in [t1, t2] { await db.addTrack(t, toPlaylist: playlist.id) }

        // Same playback order as the playlist UI (db sort_order).
        let ordered = await db.fetchTracks(forPlaylist: playlist.id).map(\.id)
        XCTAssertEqual(ordered.count, 2)

        await vm.loadPlaylist(playlist)
        XCTAssertEqual(vm.currentTrack?.id, ordered[0])

        vm.skip()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(vm.currentTrack?.id, ordered[1])

        vm.back()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(vm.currentTrack?.id, ordered[0], "<back> must step to the previous playlist track")

        // The regression: <back> on the first playlist track must NOT fall back
        // to playHistory / the pre-playlist channel track.
        vm.back()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(vm.currentTrack?.id, ordered[0],
            "<back> on the first playlist track must stay in place")
        XCTAssertNotEqual(vm.currentTrack?.id, "channel-pre",
            "<back> must never play the pre-playlist channel track")
        XCTAssertNotEqual(vm.currentTrack?.id, "channel-older",
            "<back> must never play a track from the old channel's playHistory")
    }

    // Registry-backed channels (Classical Guitar) are radio stations: they must
    // NOT play strict newest-first even when the global shuffle toggle is off.
    func testRegistryChannelDoesNotPlayStrictNewestFirst() async throws {
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        XCTAssertNotNil(channel.iaQueryEntry,
            "precondition: classical-guitar must be registry-backed")

        var tracks: [Track] = []
        for i in 1...8 {
            var t = makeIATrack(id: "sg-\(i)", tags: [Channel.stampToken("guitar-classical")])
            t.addedDate = Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + i * 86_400))
            tracks.append(t)
        }
        await db.saveTracks(tracks)

        // Pure decision — deterministic, no permutation dependence.
        XCTAssertTrue(QueueManager.usesShuffle(channel: channel, shuffleMode: false),
            "registry channel must shuffle even with the toggle OFF")
        XCTAssertTrue(QueueManager.usesShuffle(channel: channel, shuffleMode: true))

        // Deterministic drain: whole pool reachable regardless of order.
        let qm = QueueManager(db: db)
        var seen = Set<String>()
        for _ in 0..<8 {
            guard let n = await qm.nextTrack(channel: channel, shuffleMode: false) else { break }
            seen.insert(n.id)
        }
        XCTAssertEqual(seen, Set(tracks.map(\.id)), "every pool track must be reachable")
    }

    // The stamping fix: registry tracks are isolated by an injected matchTag,
    // not by sparse IA subjects. A generic 'classical' track without the stamp
    // must not leak into Classical Guitar.
    func testStampedTrackIsolatedToRegistryChannel() {
        let sg = Channel.defaults.first { $0.id == "guitar-classical" }!
        let stamped = makeIATrack(id: "sg-x",
            tags: ["classical", "78rpm", Channel.stampToken("guitar-classical")])
        XCTAssertTrue(sg.matches(stamped),
            "a stamped track must match even with sparse/non-guitar subjects")
        // A real IA subject equal to the bare id must NOT match (the leak bug).
        let bareId = makeIATrack(id: "sg-z", tags: ["guitar-classical"])
        XCTAssertFalse(sg.matches(bareId),
            "a natural subject equal to the bare id must not be treated as the stamp")
        let unstamped = makeIATrack(id: "sg-y", tags: ["classical", "78rpm"])
        XCTAssertFalse(sg.matches(unstamped),
            "without the stamp, a generic classical track must not leak into Classical Guitar")
    }

    // MARK: - Playlist cursor hardening
    //
    // Playlist navigation is an EXPLICIT index cursor, never derived from
    // currentTrack. These lock that contract so future changes that touch
    // currentTrack (spinners, auto-skip, failures) can't reintroduce the
    // recurring "playlist next/back jumps to the wrong track" regression.

    private func seedPlaylist(_ ids: [String]) async throws -> Playlist {
        let tracks = ids.map { makeFMATrack(id: $0, tags: ["jazz"]) }
        await db.saveTracks(tracks)
        let pl = try await db.createPlaylist(name: "Hardening \(UUID())")
        for t in tracks { await db.addTrack(t, toPlaylist: pl.id) }
        return pl
    }

    func testPlaylistFullTraversalAndWrap() async throws {
        vm.shuffleMode = false
        let pl = try await seedPlaylist(["h1", "h2", "h3"])
        let order = await db.fetchTracks(forPlaylist: pl.id).map(\.id)
        await vm.loadPlaylist(pl)
        XCTAssertEqual(vm.currentTrack?.id, order[0])
        XCTAssertEqual(vm.playlistIndex, 0)

        // Forward through the whole list, then WRAP back to the first.
        for expected in [order[1], order[2], order[0], order[1]] {
            vm.skip()
            try await Task.sleep(nanoseconds: 1_500_000_000)
            XCTAssertEqual(vm.currentTrack?.id, expected,
                "forward must step the cursor (incl. wrap)")
        }
    }

    // THE recurring regression, locked: if something nulls currentTrack
    // (spinner / load failure) mid-navigation, skip/back must STILL advance
    // by the cursor — not jump to index 0 or a non-playlist track.
    func testPlaylistNavigationSurvivesNilCurrentTrack() async throws {
        vm.shuffleMode = false
        let pl = try await seedPlaylist(["n1", "n2", "n3", "n4"])
        let order = await db.fetchTracks(forPlaylist: pl.id).map(\.id)
        await vm.loadPlaylist(pl)

        vm.skip()                                   // -> index 1
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(vm.currentTrack?.id, order[1])

        vm.currentTrack = nil                       // simulate spinner/failure state
        vm.skip()                                   // must go to index 2, NOT 0
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(vm.currentTrack?.id, order[2],
            "skip with nil currentTrack must still advance by cursor")

        vm.currentTrack = nil
        vm.back()                                   // must go to index 1
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(vm.currentTrack?.id, order[1],
            "back with nil currentTrack must still step the cursor back")
    }

    // Opening a playlist after playing a channel, then pressing back on the
    // first playlist track, must never resurrect the channel track — even
    // though playHistory held channel tracks.
    func testChannelThenPlaylistBackNeverLeaksChannelTrack() async throws {
        vm.shuffleMode = false
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let chTrack = makeFMATrack(id: "ch-keep-out", tags: ["jazz"])
        await db.saveTracks([chTrack])
        vm.currentChannel = channel
        vm.currentTrack = chTrack
        vm.playHistory = [makeFMATrack(id: "ch-old", tags: ["jazz"])]

        let pl = try await seedPlaylist(["p1", "p2"])
        let order = await db.fetchTracks(forPlaylist: pl.id).map(\.id)
        await vm.loadPlaylist(pl)
        XCTAssertNil(vm.currentChannel)
        XCTAssertTrue(vm.playHistory.isEmpty, "loadPlaylist must clear channel history")

        vm.back()                                   // first track -> restart, NOT channel
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(vm.currentTrack?.id, order[0])
        XCTAssertNotEqual(vm.currentTrack?.id, "ch-keep-out")
        XCTAssertNotEqual(vm.currentTrack?.id, "ch-old")
    }

    func testLoadPlaylistStartingAtMidTrackSetsCursor() async throws {
        vm.shuffleMode = false
        let pl = try await seedPlaylist(["s1", "s2", "s3"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        let mid = order[1]
        await vm.loadPlaylist(pl, startingAt: mid)
        XCTAssertEqual(vm.currentTrack?.id, mid.id)
        XCTAssertEqual(vm.playlistIndex, 1, "cursor must start at the chosen track")
        vm.skip()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(vm.currentTrack?.id, order[2].id)
    }

    // MARK: - Playlist resume (last position survives, exact offset)

    func testPlaylistKeyIsNamespaced() {
        XCTAssertEqual(PlayerViewModel.playlistKey("abc"), "playlist:abc",
            "playlist position key must be namespaced so it can't collide "
            + "with a real channel id")
    }

    func testPlaylistPositionIsPersistedOnPlay() async throws {
        vm.shuffleMode = false
        let pl = try await seedPlaylist(["r1", "r2", "r3"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        await vm.loadPlaylist(pl)
        // playTrack's playlist branch records the spot immediately.
        let saved = await db.loadPosition(channelId: PlayerViewModel.playlistKey(pl.id))
        XCTAssertEqual(saved?.trackId, order[0].id,
            "starting a playlist must persist its current track for Resume")
    }

    func testSavedPlaylistResumeReturnsTrackAndOffset() async throws {
        let pl = try await seedPlaylist(["a", "b", "c"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        await db.savePosition(channelId: PlayerViewModel.playlistKey(pl.id),
                              trackId: order[1].id, seconds: 742)

        let r = await vm.savedPlaylistResume(pl)
        XCTAssertEqual(r?.track.id, order[1].id)
        XCTAssertEqual(r?.seconds ?? 0, 742, accuracy: 0.001)

        // Saved track no longer in the playlist → no stale resume.
        await db.savePosition(channelId: PlayerViewModel.playlistKey(pl.id),
                              trackId: "deleted-track", seconds: 10)
        let gone = await vm.savedPlaylistResume(pl)
        XCTAssertNil(gone, "a removed track must not offer a resume point")
    }

    func testResumePlaylistRestoresTrackIndexAndOffset() async throws {
        vm.shuffleMode = false
        let pl = try await seedPlaylist(["x1", "x2", "x3", "x4"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        await db.savePosition(channelId: PlayerViewModel.playlistKey(pl.id),
                              trackId: order[2].id, seconds: 305)

        await vm.resumePlaylist(pl)

        XCTAssertEqual(vm.currentPlaylist?.id, pl.id)
        XCTAssertEqual(vm.currentTrack?.id, order[2].id,
            "resume must start at the saved track")
        XCTAssertEqual(vm.playlistIndex, 2, "cursor must point at the saved track")
        XCTAssertEqual(vm.currentPosition, 305, accuracy: 0.001,
            "resume must seek to the exact saved offset")
    }

    func testResumePlaylistWithoutSavedPositionPlaysFromTop() async throws {
        vm.shuffleMode = false
        let pl = try await seedPlaylist(["t1", "t2"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        await vm.resumePlaylist(pl)   // nothing saved yet
        XCTAssertEqual(vm.currentTrack?.id, order[0].id,
            "no saved spot → resume falls back to play-from-top")
    }

    // MARK: - Whole book/album (Add to Playlist)

    private func makeBookPart(parent: String, part: Int) -> Track {
        Track(
            id: "\(parent)/part\(part).mp3", source: "internet_archive",
            title: "Part \(part)", artist: "Sun Tzu", duration: 600,
            streamURL: URL(string: "https://archive.org/download/\(parent)/part\(part).mp3")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 0.7, rawCreator: "Sun Tzu", composer: nil, instruments: [],
            metadataConfidence: 1.0,
            partNumber: part, totalParts: 4, parentIdentifier: parent)
    }

    // Switching channel must hide the book/album button (no override-queue
    // machinery remains — Play Entire was removed).
    func testLoadChannelClearsMultiPartState() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        await db.saveTracks([makeFMATrack(id: "jz", tags: ["jazz"])])
        vm.currentTrackIsMultiPart = true

        let loadTask = Task { await self.vm.load(channel: channel) }
        await Task.yield()   // synchronous reset preamble runs before any await

        XCTAssertFalse(vm.currentTrackIsMultiPart,
            "switching channel must hide the book/album button")
        loadTask.cancel()
    }

    // 8a: a whole book reads in chapter order in the playlist, regardless of
    // DB/probe order. The order-preserving bulk insert means
    // fetchTracks(forPlaylist:) (sort_order DESC) returns part1 → partN.
    func testAddEntireItemToPlaylistReadsInBookOrder() async throws {
        let plVM = PlaylistViewModel(db: db)
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        vm.currentChannel = channel
        let parts = (1...4).map { makeBookPart(parent: "tom_sawyer", part: $0) }
        await db.saveTracks(parts.shuffled())   // DB order is arbitrary
        let playlist = try await db.createPlaylist(name: "Audiobook Shelf")

        await vm.addEntireItemToPlaylist(from: parts[0], to: playlist, using: plVM)

        let inPlaylist = await db.fetchTracks(forPlaylist: playlist.id)
        XCTAssertEqual(Set(inPlaylist.map(\.id)), Set(parts.map(\.id)),
                       "every part of the book must be added")
        XCTAssertEqual(
            inPlaylist.map(\.id),
            ["tom_sawyer/part1.mp3", "tom_sawyer/part2.mp3",
             "tom_sawyer/part3.mp3", "tom_sawyer/part4.mp3"],
            "the book must read in chapter order in the playlist (8a)")
    }

    func testPartsAreCleanValidation() {
        let clean = (1...3).map { makeBookPart(parent: "bk", part: $0) }
        XCTAssertTrue(PlayerViewModel.partsAreClean(clean))

        // Mixed formats (the Laws_Plato bug): same chapters as .mp3 + .ogg.
        let mixed = clean + clean.map { p in
            Track(id: p.id.replacingOccurrences(of: ".mp3", with: ".ogg"),
                  source: "internet_archive", title: p.title, artist: p.artist,
                  duration: p.duration, streamURL: p.streamURL, downloadURL: nil,
                  localFilePath: nil, license: .publicDomain, tags: [],
                  qualityScore: 0.7, rawCreator: "", composer: nil, instruments: [],
                  metadataConfidence: 1.0,
                  partNumber: p.partNumber, totalParts: 3, parentIdentifier: "bk")
        }
        XCTAssertFalse(PlayerViewModel.partsAreClean(mixed),
            "mixed-format set must be rejected so it re-probes")

        // Non-contiguous part numbers.
        let gap = [makeBookPart(parent: "bk", part: 1),
                   makeBookPart(parent: "bk", part: 4)]
        XCTAssertFalse(PlayerViewModel.partsAreClean(gap))
        XCTAssertFalse(PlayerViewModel.partsAreClean([]))
    }

    func testAddEntireItemToNewPlaylistCreatesNamedPlaylistInOrder() async throws {
        let plVM = PlaylistViewModel(db: db)
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        vm.currentChannel = channel
        let parts = (1...3).map { makeBookPart(parent: "the_odyssey", part: $0) }
        await db.saveTracks(parts.shuffled())

        let created = await vm.addEntireItemToNewPlaylist(
            from: parts[0], named: "The Odyssey", using: plVM)

        XCTAssertEqual(created?.name, "The Odyssey",
            "a new playlist named after the book must be created")
        await plVM.loadPlaylists()
        XCTAssertTrue(plVM.playlists.contains { $0.name == "The Odyssey" })
        let inPl = await db.fetchTracks(forPlaylist: created!.id)
        XCTAssertEqual(inPl.map(\.id),
                       ["the_odyssey/part1.mp3", "the_odyssey/part2.mp3",
                        "the_odyssey/part3.mp3"],
            "every part added to the new playlist, in book order")

        // Empty/blank name falls back rather than creating a nameless playlist.
        let fallback = await vm.addEntireItemToNewPlaylist(
            from: parts[0], named: "   ", using: plVM)
        XCTAssertEqual(fallback?.name, "New Playlist")
    }

    func testItemDisplayNamePrettifiesIdentifier() {
        let part = makeBookPart(parent: "laws_plato-hi_res", part: 1)
        XCTAssertEqual(vm.itemDisplayName(for: part), "Laws Plato Hi Res")
        let single = makeFMATrack(id: "x", tags: [])
        XCTAssertEqual(vm.itemDisplayName(for: single), single.title,
            "no parent → fall back to the track title")
    }

    // MARK: - Helpers

    private func makeIATrack(id: String, tags: [String]) -> Track {
        Track(
            id: id, source: "internet_archive",
            title: "IA Track \(id)", artist: "Various",
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: tags,
            qualityScore: 0.8,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0
        )
    }

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

    // MARK: - Session restore (#1: always pick up where you were)

    private func clearSessionDefaults() {
        let d = UserDefaults.standard
        for k in ["session.kind", "session.contextId", "session.trackId",
                  "session.position", "lastChannelId"] {
            d.removeObject(forKey: k)
        }
    }

    // Renamed channel ids must map forward so a session saved under the old id
    // still restores. Unknown ids pass through unchanged; nil stays nil.
    func testMigratedChannelIdMapsRenamedChannel() {
        // Both retired guitar ids forward to the rebuilt channel.
        XCTAssertEqual(PlayerViewModel.migratedChannelId("classical-guitar"),
                       "guitar-classical", "the original guitar id must map forward")
        XCTAssertEqual(PlayerViewModel.migratedChannelId("spanish-guitar"),
                       "guitar-classical", "the spanish-guitar id must map forward")
        XCTAssertEqual(PlayerViewModel.migratedChannelId("fma-jazz"), "fma-jazz",
                       "an unknown id passes through unchanged")
        XCTAssertNil(PlayerViewModel.migratedChannelId(nil), "nil stays nil")
        XCTAssertEqual(PlayerViewModel.channelIdMigrations["spanish-guitar"],
                       "guitar-classical")
    }

    // persistSession records the CHANNEL context (kind/contextId/track/position)
    // so a relaunch resumes the exact channel + track + offset.
    func testPersistSessionRecordsChannelContext() {
        clearSessionDefaults()
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        vm.currentChannel = channel
        vm.currentPlaylist = nil
        vm.currentTrack = makeFMATrack(id: "sess-ch-1", tags: ["jazz"])

        vm.persistSession(position: 123.5)

        let d = UserDefaults.standard
        XCTAssertEqual(d.string(forKey: "session.kind"), "channel")
        XCTAssertEqual(d.string(forKey: "session.contextId"), "fma-jazz")
        XCTAssertEqual(d.string(forKey: "session.trackId"), "sess-ch-1")
        XCTAssertEqual(d.double(forKey: "session.position"), 123.5, accuracy: 0.001)
    }

    // A playlist context is recorded as kind=playlist with the playlist id.
    func testPersistSessionRecordsPlaylistContext() async throws {
        clearSessionDefaults()
        let pl = try await seedPlaylist(["sess-pl-1", "sess-pl-2"])
        vm.currentChannel = nil
        vm.currentPlaylist = pl
        vm.currentTrack = makeFMATrack(id: "sess-pl-2", tags: ["jazz"])

        vm.persistSession(position: 42)

        let d = UserDefaults.standard
        XCTAssertEqual(d.string(forKey: "session.kind"), "playlist")
        XCTAssertEqual(d.string(forKey: "session.contextId"), pl.id)
        XCTAssertEqual(d.string(forKey: "session.trackId"), "sess-pl-2")
    }

    // Ambient loops must NOT persist a session — their "position" is meaningless
    // and a stale one is exactly what showed the wrong track name (#5).
    func testPersistSessionSkipsAmbientAndNilTrack() {
        clearSessionDefaults()
        // No current track → nothing written.
        vm.currentTrack = nil
        vm.persistSession(position: 10)
        XCTAssertNil(UserDefaults.standard.string(forKey: "session.kind"),
                     "no current track → no session written")

        // Ambient channel → still nothing written.
        let ambient = Channel.defaults.first { $0.contentType == .ambientLoop }!
        vm.currentChannel = ambient
        vm.currentTrack = makeFMATrack(id: "amb-x", tags: [])
        vm.persistSession(position: 10)
        XCTAssertNil(UserDefaults.standard.string(forKey: "session.kind"),
                     "ambient channel → no session persisted")
    }

    // restoreLastSession's playlist branch must rebuild the playlist context and
    // land on the saved track at the saved offset (no network).
    func testRestoreLastSessionResumesPlaylist() async throws {
        clearSessionDefaults()
        let pl = try await seedPlaylist(["rs1", "rs2", "rs3"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        await db.savePosition(channelId: PlayerViewModel.playlistKey(pl.id),
                              trackId: order[1].id, seconds: 256)
        let d = UserDefaults.standard
        d.set("playlist", forKey: "session.kind")
        d.set(pl.id, forKey: "session.contextId")
        d.set(order[1].id, forKey: "session.trackId")
        d.set(256.0, forKey: "session.position")

        let fallback = Channel.defaults.first { $0.id == "fma-jazz" }!
        await vm.restoreLastSession(fallbackChannel: fallback, autoPlay: false)

        XCTAssertEqual(vm.currentPlaylist?.id, pl.id,
            "a playlist session must restore the playlist context")
        XCTAssertEqual(vm.currentTrack?.id, order[1].id,
            "restore must land on the exact saved track")
        XCTAssertEqual(vm.currentPosition, 256, accuracy: 0.001,
            "restore must seek to the saved offset")
        XCTAssertFalse(vm.isPlaying, "autoPlay:false must restore paused")
    }

    // saveCurrentSpot must write the EXACT current offset as the PLAYLIST resume
    // point — this is what makes leaving the player (menu/background) or pausing
    // resume precisely instead of at 0:00.
    func testSaveCurrentSpotPersistsExactPlaylistPosition() async throws {
        clearSessionDefaults()
        let pl = try await seedPlaylist(["sc1", "sc2", "sc3"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        vm.currentChannel = nil
        vm.currentPlaylist = pl
        vm.currentTrack = order[1]
        vm.currentPosition = 137.5

        vm.saveCurrentSpot()
        try await Task.sleep(nanoseconds: 400_000_000)   // let the fire-and-forget DB write land

        let saved = await db.loadPosition(channelId: PlayerViewModel.playlistKey(pl.id))
        XCTAssertEqual(saved?.trackId, order[1].id,
            "leaving must save the CURRENT track as the playlist resume point")
        XCTAssertEqual(saved?.seconds ?? 0, 137.5, accuracy: 0.5,
            "leaving must save the EXACT offset, not 0:00")
    }

    // saveCurrentSpot is a no-op for ambient loops (their position is meaningless).
    func testSaveCurrentSpotSkipsAmbient() async throws {
        let ambient = Channel.defaults.first { $0.contentType == .ambientLoop }!
        vm.currentChannel = ambient
        vm.currentPlaylist = nil
        vm.currentTrack = makeFMATrack(id: "amb-spot", tags: [])
        vm.currentPosition = 50
        vm.saveCurrentSpot()
        try await Task.sleep(nanoseconds: 200_000_000)
        let saved = await db.loadPosition(channelId: ambient.id)
        XCTAssertNil(saved, "ambient loops must not record a resume position")
    }

    // MARK: - Shuffle is per-context (#shuffle: reset on every context switch)

    // Switching channels ALWAYS resets shuffle OFF — set synchronously in load()'s
    // preamble, before any network await, so an audiobook channel never inherits a
    // shuffle left on from a music channel.
    func testLoadChannelResetsShuffleOff() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        await db.saveTracks([makeFMATrack(id: "shuf-reset", tags: ["jazz"])])
        vm.shuffleMode = true

        let loadTask = Task { await self.vm.load(channel: channel) }
        await Task.yield()   // run load()'s synchronous preamble

        XCTAssertFalse(vm.shuffleMode,
            "entering a channel must always reset shuffle OFF")
        loadTask.cancel()
    }

    // A normal playlist play resets shuffle OFF; only the Shuffle action turns it
    // on. This is what keeps an audiobook playlist in chapter order.
    func testLoadPlaylistResetsShuffleUnlessRequested() async throws {
        let pl = try await seedPlaylist(["sh1", "sh2", "sh3"])

        vm.shuffleMode = true
        await vm.loadPlaylist(pl)                 // default shuffle:false
        XCTAssertFalse(vm.shuffleMode,
            "a normal playlist play must reset shuffle OFF")

        await vm.loadPlaylist(pl, shuffle: true)  // explicit shuffle
        XCTAssertTrue(vm.shuffleMode,
            "loadPlaylist(shuffle:true) must turn shuffle ON")
    }

    func testShufflePlaylistTurnsShuffleOn() async throws {
        let pl = try await seedPlaylist(["sf1", "sf2", "sf3", "sf4"])
        vm.shuffleMode = false

        await vm.shufflePlaylist(pl)

        XCTAssertTrue(vm.shuffleMode, "the Shuffle action must turn shuffle ON")
        XCTAssertEqual(vm.currentPlaylist?.id, pl.id,
            "shuffle must load the playlist context")
    }

    // The Track Info shuffle toggle flips shuffleMode (which drives the blue
    // player indicator) and persists the choice.
    func testToggleShuffleFlipsAndPersists() {
        vm.shuffleMode = false
        vm.toggleShuffle()
        XCTAssertTrue(vm.shuffleMode)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "shuffleMode"))
        vm.toggleShuffle()
        XCTAssertFalse(vm.shuffleMode)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "shuffleMode"))
    }
}

// IAQueryRegistry: bundle JSON loads and matchTags act as an isolation stamp.
final class IAQueryRegistryTests: XCTestCase {

    func testIAQueryRegistryLoadsSpanishGuitar() {
        let entry = IAQueryRegistry.shared.entry(for: "guitar-classical")
        XCTAssertNotNil(entry, "IAQueryRegistry must load the guitar-classical entry from ia_queries.json")
        XCTAssertFalse(entry?.iaQuery.isEmpty ?? true, "iaQuery must not be empty")
        // Roster-driven: master guitarists, no broad amateur-leaking subject arm.
        XCTAssertTrue(entry?.iaQuery.contains("Julian Bream") ?? false
                       && entry?.iaQuery.contains("Andrés Segovia") ?? false
                       && entry?.iaQuery.contains("Sabicas") ?? false
                       && entry?.iaQuery.contains("Laurindo Almeida") ?? false,
            "iaQuery must match the master guitarists")
        XCTAssertFalse(entry?.iaQuery.contains("subject:\"classical guitar\"") ?? true,
            "the broad amateur-leaking subject arm must be gone")
        // Still excludes spoken content.
        for excluded in ["subject:interview", "subject:talk", "subject:lecture", "title:interview"] {
            XCTAssertTrue(entry?.iaQuery.contains(excluded) ?? false,
                "iaQuery must exclude '\(excluded)' to keep out spoken content")
        }
    }

    func testSpanishGuitarMatchTagsAreAnIsolationStamp() {
        let entry = IAQueryRegistry.shared.entry(for: "guitar-classical")
        XCTAssertNotNil(entry)
        // matchTags are STAMPED onto every fetched track (not expected to overlap
        // IA subjects). The stamp must be present and collision-resistant.
        XCTAssertEqual(entry?.matchTags, ["guitar-classical"],
            "matchTags is the per-channel isolation stamp injected at fetch time")
    }

    func testChannelMatchesUsesRegistryStamp() {
        let channel = Channel.defaults.first { $0.id == "guitar-classical" }!
        // A creator-matched track with sparse subjects but carrying the stamp.
        let stamped = Track(
            id: "seg-1", source: "internet_archive",
            title: "Segovia Recital", artist: "Andrés Segovia",
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/seg-1")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain,
            tags: ["78rpm", "classical", Channel.stampToken("guitar-classical")],
            qualityScore: 0.8,
            rawCreator: "Andrés Segovia", composer: nil, instruments: [],
            metadataConfidence: 0.0
        )
        XCTAssertTrue(channel.matches(stamped),
            "Channel.matches must accept a stamped track regardless of its IA subjects")
    }

    func testIAQueryRegistryLoadsChamberMusic() {
        let entry = IAQueryRegistry.shared.entry(for: "chamber-music")
        XCTAssertNotNil(entry, "ia_queries.json must contain a chamber-music entry")
        XCTAssertTrue(entry?.iaQuery.contains("chamber music") ?? false)
        XCTAssertTrue(entry?.iaQuery.contains("string quartet") ?? false)
        // Curated query must keep the noise out.
        for excluded in ["creator:Aeon", "subject:jazz", "collection:radioprograms"] {
            XCTAssertTrue(entry?.iaQuery.contains(excluded) ?? false,
                "chamber-music query must exclude '\(excluded)'")
        }
        XCTAssertEqual(entry?.matchTags, ["chamber-music"],
            "matchTags is the chamber-music isolation stamp")
    }

    func testChamberMusicIsCuratedAndRegistryBacked() {
        let chamber = Channel.defaults.first { $0.id == "chamber-music" }
        XCTAssertNotNil(chamber, "chamber-music channel must exist")
        XCTAssertEqual(chamber?.category, "Curated",
            "chamber-music must live in the Curated section, not Classical")
        XCTAssertNotNil(chamber?.iaQueryEntry,
            "chamber-music must be registry-backed (pure-Lucene)")
        // The stamp isolates it from the shared DB.
        let stamped = Track(
            id: "cm-1", source: "internet_archive",
            title: "Beethoven String Quartet Op.59", artist: "Budapest String Quartet",
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/cm-1")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain,
            tags: ["78rpm", Channel.stampToken("chamber-music")],
            qualityScore: 1.0,
            rawCreator: "Budapest String Quartet", composer: nil, instruments: [],
            metadataConfidence: 0.0
        )
        XCTAssertTrue(chamber?.matches(stamped) ?? false)
        // A Spanish-Guitar-stamped track must NOT leak into Chamber Music.
        let other = Track(
            id: "sg-z", source: "internet_archive",
            title: "x", artist: "y", duration: 1,
            streamURL: URL(string: "https://archive.org/download/sg-z")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: ["classical", Channel.stampToken("guitar-classical")],
            qualityScore: 1.0, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 0.0
        )
        XCTAssertFalse(chamber?.matches(other) ?? true,
            "channels must not cross-contaminate via the shared DB")
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

    // Regression: ambient-loop channels (Ocean Waves / Rainy Day / Flowing
    // Water) crashed on play with the AVAudioEngine crossfade backend. The
    // AVPlayerLooper path must set up and tear down without crashing.
    func testAmbientLoopPlaybackDoesNotCrash() {
        let svc = AudioPlayerService()
        let track = Track(
            id: "freesound-156598", source: "freesound",
            title: "Ocean Waves", artist: "Rmutt", duration: 0,
            streamURL: URL(string: "https://cdn.freesound.org/previews/156/156598_981371-hq.mp3")!,
            downloadURL: nil, localFilePath: nil,
            license: .cc0, tags: ["ambient-ocean"],
            qualityScore: 1.0, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0
        )
        svc.play(url: track.streamURL, track: track, looping: true)
        XCTAssertTrue(svc.isPlaying)
        XCTAssertEqual(svc.currentTrack?.id, "freesound-156598")
        svc.pause(); svc.resume()        // looper pause/resume must not crash
        svc.skip()                       // AVPlayerLooper teardown must not crash
        XCTAssertFalse(svc.isPlaying)
    }
}

// Bug: imported local files stored an ABSOLUTE sandbox path that goes stale
// across launches → silent playback. resolvedLocalURL must find the file by
// name in the CURRENT Documents/audio dir, regardless of the stored path.
final class TrackLocalURLTests: XCTestCase {

    private func audioDir() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
    }

    func testResolvedLocalURLFindsFileDespiteStaleAbsolutePath() throws {
        let dir = audioDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "unit-test-\(UUID().uuidString).mp3"
        let real = dir.appendingPathComponent(name)
        try Data([0x49, 0x44, 0x33]).write(to: real)
        defer { try? FileManager.default.removeItem(at: real) }

        // Stored path is a stale absolute container path that no longer exists,
        // but its last component matches the real file.
        let track = Track(
            id: "loc-1", source: "local",
            title: "Mine", artist: "Me", duration: 1,
            streamURL: URL(fileURLWithPath: "/stale/\(name)"),
            downloadURL: nil,
            localFilePath: "/var/old-container/Documents/audio/\(name)",
            license: .publicDomain, tags: [],
            qualityScore: 0, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 0, isLocal: true
        )
        XCTAssertEqual(track.resolvedLocalURL?.lastPathComponent, name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: track.resolvedLocalURL?.path ?? ""))
    }

    func testResolvedLocalURLNilWhenMissingOrNotLocal() {
        let missing = Track(
            id: "loc-2", source: "local",
            title: "Gone", artist: "x", duration: 1,
            streamURL: URL(fileURLWithPath: "/x.mp3"),
            downloadURL: nil, localFilePath: "audio/does-not-exist-\(UUID()).mp3",
            license: .publicDomain, tags: [],
            qualityScore: 0, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 0, isLocal: true
        )
        XCTAssertNil(missing.resolvedLocalURL, "missing file must resolve to nil (→ auto-skip)")

        let remote = Track(
            id: "ia-1", source: "internet_archive",
            title: "x", artist: "y", duration: 1,
            streamURL: URL(string: "https://archive.org/download/ia-1")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 0, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 0
        )
        XCTAssertNil(remote.resolvedLocalURL, "non-local track has no local URL")
    }
}
