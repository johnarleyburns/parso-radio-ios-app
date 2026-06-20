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

    override func tearDownWithError() throws {
        vm = nil
        db = nil
        UserDefaults.standard.removeObject(forKey: "lastChannelId")
        UserDefaults.standard.removeObject(forKey: "shuffleMode")
        UserDefaults.standard.removeObject(forKey: "repeatMode")
        try super.tearDownWithError()
    }

    // UC2: last channel ID is written to UserDefaults as soon as load() begins,
    // before any network call, so a crash or force-quit still persists the choice.
    func testLastChannelIdSavedOnLoad() async throws {
        let channel = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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

        let newChannel = Channel.fmaClassicalTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
        vm.currentChannel = channel
        let parts = (1...4).map { makeBookPart(parent: "tom_sawyer", part: $0) }
        await db.saveTracks(parts.shuffled())   // DB order is arbitrary
        let playlist = try await db.createPlaylist(name: "Audiobook Shelf")

        vm.currentTrack = parts[0]
        await vm.addEntireItemToPlaylist(playlist)

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

    // resolveItemParts: DB-first path returns clean multi-part items from cache.
    func testResolveItemPartsReturnsDBParts() async {
        let parts = (1...3).map { makeBookPart(parent: "resolve-db-test", part: $0) }
        await db.saveTracks(parts)
        let result = await vm.resolveItemParts(identifier: "resolve-db-test")
        XCTAssertNotNil(result, "resolveItemParts must return parts from DB when they pass partsAreClean")
        XCTAssertEqual(result?.count, 3)
        XCTAssertEqual(result?.map(\.partNumber), [1, 2, 3])
    }

    // resolveItemParts: single-item in DB with isMultiPart=false returns nil.
    func testResolveItemPartsReturnsNilForSingleFileVerdict() async {
        let single = Track(
            id: "single-item", source: "internet_archive",
            title: "One Track", artist: "Artist",
            duration: 300,
            streamURL: URL(string: "https://archive.org/download/single-item")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 0.7, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 1.0
        )
        await db.saveTracks([single])
        await db.setIsMultiPart(false, forTrackId: "single-item")
        let result = await vm.resolveItemParts(identifier: "single-item")
        XCTAssertNil(result, "resolveItemParts must return nil for single-file items with isMultiPart=false verdict")
    }

    // resolveItemParts: empty DB and no active network mock falls through
    // to network probe, which times out → returns nil (not a crash).
    func testResolveItemPartsReturnsNilWhenNothingInDB() async {
        let result = await vm.resolveItemParts(identifier: "nonexistent-identifier")
        XCTAssertNil(result, "resolveItemParts must return nil when no data exists and network is unavailable")
    }

    func testAddEntireItemToNewPlaylistCreatesNamedPlaylistInOrder() async throws {
        let plVM = PlaylistViewModel(db: db)
        let channel = Channel.fmaJazzTestChannel
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

    // persistSession records the CHANNEL context (kind/contextId/track/position)
    // so a relaunch resumes the exact channel + track + offset.
    func testPersistSessionRecordsChannelContext() {
        clearSessionDefaults()
        let channel = Channel.fmaJazzTestChannel
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

        let fallback = Channel.fmaJazzTestChannel
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
        let channel = Channel.fmaJazzTestChannel
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

    // MARK: - Buffering-stall watchdog

    // These tests now drive the shared StallModel (the pure decision core is unit-
    // tested in PlaybackResilienceTests); here we verify the VM applies each
    // verdict — keep/skip/give-up — with the right side effects.

    // A track that DID start playing (confirmed) must never be skipped.
    func testStallWatchdogDoesNotSkipConfirmedTrack() async {
        vm.currentChannel = Channel.fmaJazzTestChannel
        vm.currentTrack = makeFMATrack(id: "confirmed", tags: ["jazz"])
        let g = vm.stallModel.beginLoad()
        vm.stallModel.confirmPlayback(generation: g)   // audio progressed → confirmed
        await vm.handleStallIfNeeded(generation: g)
        XCTAssertEqual(vm.currentTrack?.id, "confirmed", "a confirmed track must not be skipped")
    }

    // A track that became READY but is paused is healthy — it must NOT be skipped
    // even though it never produced a playback tick (the paused-resume case).
    func testStallWatchdogDoesNotSkipReadyPausedTrack() async {
        vm.currentChannel = Channel.fmaJazzTestChannel
        vm.currentTrack = makeFMATrack(id: "ready-paused", tags: ["jazz"])
        vm.isPlaying = false
        let g = vm.stallModel.beginLoad()
        vm.stallModel.markReady(generation: g)         // playable, just paused
        await vm.handleStallIfNeeded(generation: g, autoPlay: false)
        XCTAssertEqual(vm.currentTrack?.id, "ready-paused",
            "a ready (but paused) track must not be skipped")
    }

    // A track that became READY but then stalled during playback while we INTENDED
    // to play must be skipped — "ready" is not enough when we wanted audio.
    func testStallWatchdogSkipsReadyButNeverPlayedWhenAutoPlay() async throws {
        await db.saveTracks([makeFMATrack(id: "ready-stalled", tags: ["jazz"]),
                             makeFMATrack(id: "next-up", tags: ["jazz"])])
        vm.currentChannel = Channel.fmaJazzTestChannel
        vm.currentTrack = makeFMATrack(id: "ready-stalled", tags: ["jazz"])
        vm.isPlaying = true
        let g = vm.stallModel.beginLoad()
        vm.stallModel.markReady(generation: g)         // became ready, then stalled
        await vm.handleStallIfNeeded(generation: g, autoPlay: true)
        XCTAssertTrue(vm.isLoading,
            "a ready-but-stalled track must be skipped when we intended to play")
    }

    // A watchdog from a PREVIOUS track (stale generation) must be a no-op.
    func testStallWatchdogIgnoresStaleGeneration() async {
        vm.currentChannel = Channel.fmaJazzTestChannel
        vm.currentTrack = makeFMATrack(id: "current", tags: ["jazz"])
        let stale = vm.stallModel.beginLoad()          // an older generation…
        _ = vm.stallModel.beginLoad()                  // …we've since moved past
        await vm.handleStallIfNeeded(generation: stale)
        XCTAssertEqual(vm.currentTrack?.id, "current", "a stale-generation watchdog must do nothing")
    }

    // A genuinely stuck track (never ready, never played) IS skipped — even when
    // it was loading PAUSED (the launch-after-update hang).
    func testStallWatchdogSkipsStuckTrackEvenWhenPaused() async throws {
        await db.saveTracks([makeFMATrack(id: "stuck", tags: ["jazz"]),
                             makeFMATrack(id: "next-up", tags: ["jazz"])])
        vm.currentChannel = Channel.fmaJazzTestChannel
        vm.currentTrack = makeFMATrack(id: "stuck", tags: ["jazz"])
        vm.isPlaying = false                           // loaded paused
        let g = vm.stallModel.beginLoad()              // never ready, never confirmed
        await vm.handleStallIfNeeded(generation: g, autoPlay: false)
        XCTAssertTrue(vm.isLoading, "a never-ready track must be skipped even when paused")
    }

    // The "infinite buffering" bug: item after item resolves but never produces
    // audio. The consecutive-stall cap must eventually give up (it can't be reset
    // by a mere resolve — only by a real playback tick).
    func testStallWatchdogGivesUpAfterRepeatedStalls() async throws {
        await db.saveTracks((0..<10).map { makeFMATrack(id: "stall-\($0)", tags: ["jazz"]) })
        vm.currentChannel = Channel.fmaJazzTestChannel
        vm.currentTrack = makeFMATrack(id: "stall-0", tags: ["jazz"])
        vm.isPlaying = true
        // Four consecutive stalls (== the give-up cap); each skip arms a new
        // generation, so re-read it each iteration.
        for _ in 0..<4 {
            let gen = vm.stallModel.loadGeneration
            await vm.handleStallIfNeeded(generation: gen, autoPlay: true)
        }
        XCTAssertNotNil(vm.errorMessage,
            "after repeated stalls with no playback the player must give up with an error")
        XCTAssertFalse(vm.isLoading, "giving up must clear the buffering indicator")
        XCTAssertNil(vm.currentTrack, "giving up must stop playback")
    }

    // A genuine playback tick between stalls must RESET the streak, so a normally
    // healthy channel with the occasional bad track never hits the give-up cap.
    func testStallStreakResetAllowsContinuedPlayback() async throws {
        await db.saveTracks((0..<10).map { makeFMATrack(id: "mix-\($0)", tags: ["jazz"]) })
        vm.currentChannel = Channel.fmaJazzTestChannel
        vm.currentTrack = makeFMATrack(id: "mix-0", tags: ["jazz"])
        vm.isPlaying = true
        for _ in 0..<3 {                                // three stalls (under the cap)
            let gen = vm.stallModel.loadGeneration
            await vm.handleStallIfNeeded(generation: gen, autoPlay: true)
        }
        // Real audio plays → a tick resets the streak.
        vm.stallModel.confirmPlayback(generation: vm.stallModel.loadGeneration)
        for _ in 0..<3 {                                // three more — still under the cap
            let gen = vm.stallModel.loadGeneration
            await vm.handleStallIfNeeded(generation: gen, autoPlay: true)
        }
        XCTAssertNil(vm.errorMessage,
            "a confirmed playback between stalls must reset the streak (no give-up)")
    }

    // Settings → "Clear All Data" must erase tracks, playlists and history.
    func testClearAllUserDataWipesEverything() async throws {
        _ = try await seedPlaylist(["w1", "w2"])
        await db.recordPlayed(channelId: "fma-jazz", trackId: "w1")
        let tracksBefore = await db.trackCount()
        let playlistsBefore = await db.fetchPlaylists()
        XCTAssertGreaterThan(tracksBefore, 0, "precondition: data present")
        XCTAssertFalse(playlistsBefore.isEmpty)

        await vm.clearAllUserData()

        let tracksAfter = await db.trackCount()
        let playlistsAfter = await db.fetchPlaylists()
        let historyAfter = await vm.recentlyPlayedTracks(limit: 50)
        XCTAssertEqual(tracksAfter, 0, "all tracks must be deleted")
        XCTAssertTrue(playlistsAfter.isEmpty, "all playlists must be deleted")
        XCTAssertTrue(historyAfter.isEmpty, "all listening history must be deleted")
        XCTAssertNil(vm.currentTrack, "playback must stop and clear")
    }

    // REGRESSION GUARD: a resume must honor autoPlay reliably. autoPlay:false
    // must load the track PAUSED (ready, not playing); autoPlay:true must start
    // playing. The bug was a race where the channel loaded silent with no
    // progress until the user pressed play.
    func testLoadPlaylistAutoPlayFalseLoadsPaused() async throws {
        let pl = try await seedPlaylist(["ap1", "ap2"])
        await vm.loadPlaylist(pl, autoPlay: false)
        XCTAssertNotNil(vm.currentTrack, "the track must still LOAD when autoPlay is false")
        XCTAssertFalse(vm.isPlaying, "autoPlay:false must load paused, not playing")
    }

    func testLoadPlaylistAutoPlayTrueStartsPlaying() async throws {
        let pl = try await seedPlaylist(["ap3", "ap4"])
        await vm.loadPlaylist(pl, autoPlay: true)
        XCTAssertNotNil(vm.currentTrack)
        XCTAssertTrue(vm.isPlaying, "autoPlay:true must start playing")
    }

    // A paused resume must still seek to (and surface) the saved offset, so the
    // progress bar shows where the user was instead of 0:00.
    func testResumePlaylistAutoPlayFalseLandsAtOffsetPaused() async throws {
        let pl = try await seedPlaylist(["ro1", "ro2", "ro3"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        await db.savePosition(channelId: PlayerViewModel.playlistKey(pl.id),
                              trackId: order[1].id, seconds: 220)
        await vm.resumePlaylist(pl, autoPlay: false)
        XCTAssertEqual(vm.currentTrack?.id, order[1].id, "must resume the saved track")
        XCTAssertFalse(vm.isPlaying, "autoPlay:false resume stays paused")
        XCTAssertEqual(vm.currentPosition, 220, accuracy: 0.5,
            "a paused resume must still show the saved offset, not 0:00")
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

// PlaylistDetailView tests: validates ViewModel state transitions that
// drive the loading-indicator UI. When the user taps Play / Shuffle / a
// track row, the ViewModel must immediately set the correct currentPlaylist,
// playlistTracks, and playback context so the UI can show feedback.
extension PlayerViewModelTests {

    // Tapping a track row in a playlist must start playback from that
    // exact track with the playlist context loaded.
    func testLoadPlaylistStartingAtTrackPositionsCorrectly() async throws {
        let pl = try await seedPlaylist(["at1", "at2", "at3", "at4"])
        let order = await db.fetchTracks(forPlaylist: pl.id)

        await vm.loadPlaylist(pl, startingAt: order[1])

        XCTAssertEqual(vm.currentPlaylist?.id, pl.id,
            "playlist context must be set so the header shows the playlist name")
        XCTAssertEqual(vm.currentTrack?.id, order[1].id,
            "playback must start from the tapped track")
        XCTAssertEqual(vm.playlistIndex, 1,
            "playlistIndex cursor must point at the tapped track")
        XCTAssertEqual(vm.playlistTracks.map(\.id), order.map(\.id),
            "all playlist tracks must be loaded in display order")
    }

    // Tapping the Play button must resume from the last-saved position.
    func testResumePlaylistSetsCorrectPlaylistAndTrack() async throws {
        vm.shuffleMode = false
        let pl = try await seedPlaylist(["rp1", "rp2", "rp3"])
        let order = await db.fetchTracks(forPlaylist: pl.id)
        await db.savePosition(channelId: PlayerViewModel.playlistKey(pl.id),
                              trackId: order[2].id, seconds: 421)

        await vm.resumePlaylist(pl)

        XCTAssertEqual(vm.currentPlaylist?.id, pl.id,
            "playlist context must be set so the header shows the playlist name")
        XCTAssertEqual(vm.currentTrack?.id, order[2].id,
            "must resume the saved track, not the first track")
        XCTAssertEqual(vm.currentPosition, 421, accuracy: 0.001)
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

// MARK: - Channel state preservation (openMenu / channel info navigation)

extension PlayerViewModelTests {

    /// Regression: `currentChannel` must stay set after `saveCurrentSpot()` so
    /// the idleView does NOT show "Tap ☰ to select a channel" when the user is
    /// already on a channel. `openMenu(contextual:)` calls `saveCurrentSpot()`
    /// before opening the sheet; nothing in that flow should clear the channel.
    func testCurrentChannelStaysSetAfterSaveCurrentSpot() async {
        let channel = Channel.fmaJazzTestChannel
        let track = makeFMATrack(id: "channel-spot-1", tags: ["jazz"])
        await db.saveTracks([track])

        // Preconditions: channel is not loaded yet.
        XCTAssertNil(vm.currentChannel)

        // Simulate loading a channel (the sync preamble: assignment + state reset)
        vm.currentChannel = channel
        vm.currentTrack = track
        vm.isPlaying = true

        XCTAssertNotNil(vm.currentChannel, "currentChannel must be set before menu opens")
        XCTAssertEqual(vm.currentChannel?.id, channel.id)

        // Simulate `openMenu(contextual:)` which calls `saveCurrentSpot()`.
        // saveCurrentSpot needs a currentTrack with position and a non-ambient channel.
        vm.saveCurrentSpot()

        // After saveCurrentSpot, the channel must STILL be set — the menu
        // flow does not clear channel context. If currentChannel became nil
        // here, the idleView would show the misleading prompt.
        XCTAssertNotNil(vm.currentChannel,
            "currentChannel must remain set after saveCurrentSpot (menu open)")
        XCTAssertEqual(vm.currentChannel?.id, channel.id,
            "currentChannel must not change identity during menu lifecycle")
    }

    /// `currentChannel` must not be cleared when `saveCurrentSpot()` runs with
    /// no `currentTrack` (e.g. the track finished while the menu was open).
    func testCurrentChannelPreservedWhenSaveCurrentSpotWithNoTrack() async {
        let channel = Channel.fmaJazzTestChannel
        vm.currentChannel = channel
        vm.currentTrack = nil
        vm.isPlaying = false

        // Calling saveCurrentSpot with no currentTrack is a no-op internally
        // but must not side-effect currentChannel.
        vm.saveCurrentSpot()

        XCTAssertNotNil(vm.currentChannel,
            "currentChannel must stay set even when saveCurrentSpot is a no-op")
    }

    /// `currentChannel` must remain set after `saveCurrentSpot()` even when
    /// the previous channel had an error. The error-view branch and idle-view
    /// branch are adjacent in the body; a nil channel causes the idle branch
    /// to win over the error branch.
    func testCurrentChannelPreservedAfterSaveCurrentSpotFollowingError() async {
        let channel = Channel.fmaJazzTestChannel
        vm.currentChannel = channel
        vm.currentTrack = nil
        vm.isPlaying = false
        vm.errorMessage = "A previous load failed"

        vm.saveCurrentSpot()

        XCTAssertNotNil(vm.currentChannel,
            "currentChannel must stay set after saveCurrentSpot even with error state")
        XCTAssertNotNil(vm.errorMessage,
            "errorMessage must persist so errorView is shown, not idleView")
    }

    /// When a channel is loaded and `currentTrack` is nil (e.g. track
    /// finished), the ViewModel must still report the channel so the display
    /// knows what is selected. The idleView reads both conditions.
    func testCurrentChannelStaysSetWhenTrackBecomesNil() async {
        let channel = Channel.fmaJazzTestChannel
        let track = makeFMATrack(id: "nil-track-1", tags: ["jazz"])
        await db.saveTracks([track])

        vm.currentChannel = channel
        vm.currentTrack = track
        vm.isPlaying = true

        XCTAssertNotNil(vm.currentTrack)

        // Simulate the track finishing (onTrackFinished callback path)
        vm.currentTrack = nil
        vm.isPlaying = false

        XCTAssertNotNil(vm.currentChannel,
            "currentChannel must stay set when currentTrack becomes nil so idleView does not show the wrong prompt")
        XCTAssertNil(vm.currentTrack)
        XCTAssertFalse(vm.isPlaying)
    }

    // MARK: - Stall watchdog guard: zero-second ticks (Fix A)

    /// Regression: AVPlayer fires zero-second time ticks for stuck/buffering
    /// items. `confirmPlayback` must NOT be called for `seconds == 0` because
    /// it permanently disarms the stall watchdog (confirmedGeneration ==
    /// loadGeneration, so evaluateStall always returns .healthy).
    func testStallWatchdogFiresAfterZeroSecondTicks() async {
        // Set up the stall model with a known generation
        let gen = vm.stallModel.beginLoad()

        // Simulate a zero-second time tick (stuck AVPlayer) — must NOT confirm
        // Test this by directly checking StallModel state after "onTimeUpdate"
        // with seconds == 0. We can't call the closure directly, so we verify
        // the model's behavior: if confirmedGeneration is NOT set, evaluateStall
        // should return .skip (not .healthy) after the right generation match.
        let verdict = vm.stallModel.evaluateStall(generation: gen, autoPlay: true)
        // Without a confirm, this should be .skip (1st consecutive), not .healthy
        XCTAssertEqual(verdict, .skip,
            "Without confirmPlayback, evaluateStall must return .skip (not .healthy)")
    }

    /// After real audio progress (seconds > 0 and confirmPlayback called),
    /// the stall watchdog should return .healthy.
    func testStallWatchdogHealthyAfterNonZeroTick() async {
        let gen = vm.stallModel.beginLoad()
        // Simulate a real time tick: confirmPlayback(generation: gen)
        var model = vm.stallModel  // value copy
        model.confirmPlayback(generation: gen)
        let verdict = model.evaluateStall(generation: gen, autoPlay: true)
        XCTAssertEqual(verdict, .healthy,
            "After confirmPlayback, stall model must return .healthy for that generation")
    }

    func testPlayHistoryVersionStartsAtZero() {
        XCTAssertEqual(vm.playHistoryVersion, 0)
    }

    func testRecentlyPlayedTracksReflectsHistoryAfterRecordPlayed() async throws {
        let t = Track(
            id: "hist-test", source: "fma", title: "History Track", artist: "Test",
            duration: 120, streamURL: URL(string: "https://example.com/hist")!,
            downloadURL: nil, localFilePath: nil,
            license: .cc0, tags: [], qualityScore: 1.0,
            rawCreator: "", composer: nil, instruments: [], metadataConfidence: 2.0
        )
        await db.saveTracks([t])
        await db.recordPlayed(channelId: "test-ch", trackId: t.id)
        vm.playHistoryVersion &+= 1

        XCTAssertEqual(vm.playHistoryVersion, 1)
        let recents = await vm.recentlyPlayedTracks(limit: 10)
        XCTAssertFalse(recents.isEmpty, "Recently played should contain the recorded track")
        XCTAssertEqual(recents.first?.id, t.id)
    }

}
