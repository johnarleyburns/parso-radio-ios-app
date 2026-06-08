import Foundation
import SwiftUI
import UIKit
import MediaPlayer
import AVFoundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String?
    @Published var errorMessage: String?
    // Brief, non-destructive notice (e.g. "you're offline") shown as an alert
    // without disturbing whatever is currently playing.
    @Published var transientMessage: String?
    @Published var currentPosition: Double = 0
    @Published var trackDuration: Double?
    @Published var isScrubbing: Bool = false
    @Published var shuffleMode: Bool = UserDefaults.standard.bool(forKey: "shuffleMode")
    @Published var repeatMode: AudioPlayerService.RepeatMode = {
        let raw = UserDefaults.standard.string(forKey: "repeatMode") ?? ""
        return AudioPlayerService.RepeatMode(rawValue: raw) ?? .off
    }()
    @Published var channelTrackCount: Int = 0
    @Published var channelMostRecentDate: Date? = nil
    @Published var channelDescription: String = ""
    @Published var currentArtwork: UIImage? = nil
    @Published var artworkDominantColor: Color = .accentColor
    @Published var currentPlaylist: Playlist? = nil
    // Drives the "Add Book/Album to Playlist" button. Set false on every
    // track change; set true once the silent probe confirms a multi-file item.
    @Published var currentTrackIsMultiPart: Bool = false
    // Multi-part summary for the current item, filled by the silent probe:
    // total chapters/tracks, summed runtime, and which part is playing (1-based,
    // nil if unknown). Surfaced on the track box ("Part m of n") and Track Info.
    @Published var currentItemChapterCount: Int = 0
    @Published var currentItemTotalDuration: Double = 0
    @Published var currentItemPartIndex: Int? = nil

    // Sleep timer: non-nil endsAt → a Task is counting down to pause(); the
    // "End of Track" flag stops at the next natural onTrackFinished.
    @Published var sleepTimerEndsAt: Date? = nil
    @Published var sleepAtEndOfTrack: Bool = false
    private var sleepTimerTask: Task<Void, Never>? = nil

    // Bookmarks for the currently-playing track. Reloaded on track change.
    @Published var bookmarksForCurrentTrack: [Bookmark] = []
    // Mirrors audioPlayer.playbackRate (Float) as a Double for SwiftUI bindings.
    @Published var playbackRate: Double

    let audioPlayer: any AudioEngine

    // Internal so the Curator UI can drive the DB through the same model layer.
    let db: DatabaseService
    let archiveService: InternetArchiveService
    private let fmaService: FMAService
    private let oxfordService: OxfordLecturesService
    private let podcastService: PodcastRSSService
    private let ambientService: AmbientStaticService
    private let queueManager: QueueManager
    private let downloadManager: DownloadManager
    // Resolves the deterministic on-disk path for a downloaded track so
    // playback prefers a local file over re-streaming from the Internet Archive.
    private let fileStorage = FileStorageService()
    @Published var currentChannel: Channel?

    /// When a curator audition fails (no channel, no playlist), the track ID
    /// is captured here BEFORE `currentTrack` is cleared. Curator views use
    /// this to show a yellow warning icon and flash on the specific failed
    /// row even though `currentTrack` is nil by the time errorMessage fires.
    @Published var failedAuditionTrackId: String?

    // Look-ahead cache: pre-resolved IA audio URLs so track transitions are gap-free.
    private var prefetchedURLs: [String: URL] = [:]
    // In-session multi-file probe cache, keyed by bare IA identifier.
    //   key absent      → not yet probed this session
    //   value .some(nil) → confirmed single-file (never probe again)
    //   value [Track]    → confirmed multi-file, parts in part order
    // Cleared on channel switch (IA item file lists are immutable per session).
    private var itemPartsCache: [String: [Track]?] = [:]
    // Throttle spoken-word position saves to once every 5 s (onTimeUpdate fires 4×/s).
    private var lastPositionSaveTime: Double = -5
    // Timestamp of the most recent scrub movement. The scrub guard in
    // onTimeUpdate auto-expires off this so an interrupted drag (whose .onEnded
    // never fired) can't latch isScrubbing true and freeze the timer / strand
    // "Buffering…".
    private var lastScrubActivity: Date = .distantPast

    // UC3: track history for backward navigation (most-recent last, cap historyLimit).
    var playHistory: [Track] = []
    let historyLimit = 50
    // Playlist mode: the ordered tracks of the active playlist plus an
    // EXPLICIT cursor. Navigation steps the cursor — it is never derived from
    // currentTrack (which other code nulls for spinners/failures). This makes
    // playlist next/back robust regardless of currentTrack mutations.
    var playlistTracks: [Track] = []
    var playlistIndex: Int = 0
    // Guards against double-advance when skip() fires onTrackFinished before the Task runs.
    private var isSkipping = false
    // We auto-skip ONLY on a true failure: the stream URL can't be resolved
    // within loadTimeout (no network response), or the AVPlayerItem reports
    // .failed (dead URL / 404 / undecodable). A merely-slow connection is NOT
    // skipped — AVPlayer waits and rebuffers. Capped so a channel where every
    // track is genuinely unplayable doesn't loop forever.
    private let loadTimeout: Double
    // Buffering-stall watchdog: if a track never produces a real playback tick
    // within stallTimeout, it's stuck buffering. ALL the reliability decisions —
    // is this a stale watchdog, is the item healthy, skip, or give up after too
    // many consecutive stalls with no audio ("infinite buffering") — are made by
    // the pure, unit-tested StallModel (see PlaybackResilience / PLAYBACK-DESIGN).
    // The view model only owns the timer plumbing and applies the verdict.
    private let stallTimeout: Double
    // internal (not private) so tests can drive the watchdog's decision directly.
    var stallModel = StallModel(maxConsecutiveSkips: 4)
    private var stallWatchdog: Task<Void, Never>?
    // Retry transient resolve/load failures (timeout, 5xx, connection lost) with
    // exponential backoff before skipping; permanent failures (404/unsupported)
    // skip immediately. Per-item attempt counts; cleared on success. Pure policy.
    private let retryPolicy: RetryPolicy
    private var loadAttempts: [String: Int] = [:]
    // After this many items fail to RESOLVE in a row, stop (distinct from the
    // stall give-up, which is for items that resolve but never produce audio).
    private let maxConsecutiveLoadFailures = 8
    private var consecutiveLoadFailures = 0
    // Bumped every time the playback CONTEXT changes (channel / playlist /
    // search result). playTrack captures it on entry and re-checks right before
    // it commits audio: a track that was still resolving when the user switched
    // contexts is abandoned instead of starting — otherwise a playlist chapter
    // mid-resolve could begin playing under the channel we just switched to,
    // showing the channel's name (the "Cafe Lento plays part 9 of my book" bug).
    private var playbackContextToken = 0
    private var isAuditioning = false
    private var preAuditionState: (
        channel: Channel?, playlist: Playlist?,
        playlistTracks: [Track], playlistIndex: Int,
        playHistory: [Track], shuffleMode: Bool,
        track: Track?, position: Double, isPlaying: Bool
    )?

    init(
        db: DatabaseService,
        archiveService: InternetArchiveService,
        fmaService: FMAService,
        queueManager: QueueManager,
        audioPlayer: any AudioEngine,
        downloadManager: DownloadManager,
        oxfordService: OxfordLecturesService = OxfordLecturesService(),
        podcastService: PodcastRSSService = PodcastRSSService(),
        ambientService: AmbientStaticService = AmbientStaticService(),
        // Injectable so tests can shrink the watchdog/retry to milliseconds and
        // stay within the single fast CI job (see PLAYBACK-TESTING-PLAN.md).
        loadTimeout: Double = 10,
        stallTimeout: Double = 20,
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.db = db
        self.archiveService = archiveService
        self.fmaService = fmaService
        self.oxfordService = oxfordService
        self.podcastService = podcastService
        self.ambientService = ambientService
        self.queueManager = queueManager
        self.audioPlayer = audioPlayer
        self.downloadManager = downloadManager
        self.loadTimeout = loadTimeout
        self.stallTimeout = stallTimeout
        self.retryPolicy = retryPolicy
        self.playbackRate = Double(audioPlayer.playbackRate)

        // Evict stale tracks on launch if DB is large (>5 000 rows, older than 30 days).
        Task { [weak self] in
            guard let self else { return }
            let count = await self.db.trackCount()
            if count > 5000 { await self.db.evictOldTracks() }
        }
        // Seed the live curation snapshot from the DB on launch so curated
        // channels show the curator's verdicts immediately (and so the
        // Documents/curation.json file reflects the current DB).
        Task { [db] in await LiveCurationStore.shared.reload(from: db) }

    // Issue 3: save isPlaying so cold-start can decide whether to auto-play.
    NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                UserDefaults.standard.set(self.isPlaying, forKey: "wasPlayingOnQuit")
                // Safety-net: never lose the user's spot — save the EXACT
                // playlist/channel resume point + autosave + session snapshot on
                // resign (covers backgrounding and app updates).
                self.saveCurrentSpot()
            }
        }

        // Returning to the app: the system / another app may have paused us
        // while backgrounded without notifying. Resync so the wheel shows the
        // correct play vs. pause icon.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.audioPlayer.syncPlaybackState()
                self.isPlaying = self.audioPlayer.isPlaying
            }
        }

        audioPlayer.onPreviousTrack = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.playPreviousTrack()
            }
        }

        audioPlayer.onTrackFinished = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // skip() already scheduled an advance; ignore the finish notification.
                if self.isSkipping { self.isSkipping = false; return }
                // Sleep timer "End of Track" — stop here instead of advancing.
                if self.sleepAtEndOfTrack {
                    self.sleepAtEndOfTrack = false
                    self.sleepTimerEndsAt = nil
                    self.audioPlayer.pause()
                    self.isPlaying = false
                    return
                }
                // Ambient loop channels: seek back to the beginning instead of advancing.
                if let channel = self.currentChannel, channel.contentType == .ambientLoop {
                    self.audioPlayer.seek(to: 0)
                    self.audioPlayer.resume()
                    self.isPlaying = true
                    self.currentPosition = 0
                    return
                }
                // Natural finish — the track played to its end. Drop the
                // autosave so future revisits start at zero (they've heard it).
                if let finishedId = self.currentTrack?.id {
                    self.deleteAutosaveForTrack(finishedId)
                }
                // Natural finish: clear saved position so the next track starts fresh.
                if let channel = self.currentChannel, channel.contentType == .spokenWord {
                    await self.db.clearPosition(channelId: channel.id)
                }
                await self.advanceToNext()
            }
        }

        // The item became playable: publish its real duration so the progress
        // bar / elapsed time appear immediately — even for a resume that starts
        // PAUSED (IA search docs carry no runtime, so this is often the first
        // time we learn the duration), and clear the loading indicator.
        audioPlayer.onReady = { [weak self] duration in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Item is playable → mark ready so a paused-but-ready resume is
                // treated as healthy by the watchdog (and not skipped).
                self.stallModel.markReady(generation: self.stallModel.loadGeneration)
                if duration > 0 { self.trackDuration = duration }
                // Clear "Buffering…" on ready ONLY when we don't intend to play
                // (a paused resume — no time tick will come, so the spinner has
                // to go now). For autoPlay loads the spinner stays until the
                // first real time tick (onTimeUpdate) so the user sees feedback
                // during the few hundred ms AVPlayer takes to prebuffer audio
                // after .readyToPlay — the "sits at 0:00 with no spinner" bug.
                if self.isLoading, !self.isPlaying {
                    self.isLoading = false
                    self.loadingMessage = nil
                }
            }
        }

        audioPlayer.onNonAudio = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let track = self.currentTrack else { return }
                Log.playback.warning("Non-audio material detected: \(track.id)")
                self.errorMessage = "Non-audio material — skipping"
                self.isLoading = false
                self.loadingMessage = nil
                self.isPlaying = false
                self.audioPlayer.skip()
                self.currentTrack = nil
                self.trackDuration = nil
                // Invalidate cache so re-visit doesn't hit the same bad file
                self.audioPlayer.invalidateStreamingCache(for: track.id)
                // Advance to next if in a channel/playlist
                if self.currentChannel != nil || self.currentPlaylist != nil {
                    await self.advanceToNext(autoPlay: true)
                }
            }
        }

        audioPlayer.onTimeUpdate = { [weak self] seconds in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // A periodic time tick only fires while the player is actually
                // progressing (never while buffering/stalled), so any tick means
                // THIS track is genuinely playing — confirm it (which also breaks
                // the consecutive-stall streak; a mere resolve must NOT reset it).
                //
                // GUARD: AVPlayer's addPeriodicTimeObserver fires on a TIMER
                // (every 0.25 s), NOT based on audio progress. A stuck/buffering
                // item can fire with seconds == 0.0 indefinitely. Without this
                // guard, a zero-second tick permanently disarms the stall
                // watchdog (confirmPlayback sets confirmedGeneration, and
                // evaluateStall then always returns .healthy), causing the
                // "spins forever" bug on unplayable IA tracks (e.g. Navarra).
                if seconds > 0 {
                    self.stallModel.confirmPlayback(generation: self.stallModel.loadGeneration)
                }
                // The first time tick PAST zero means audio is genuinely
                // progressing — hide the loading indicator. This MUST run even
                // while isScrubbing: an interrupted wheel drag could otherwise
                // strand "Buffering…" on a track that is actually playing. (The
                // observer can fire once at 0 before playback actually starts,
                // so the >0.1 guard avoids clearing too early.)
                if self.isLoading, seconds > 0.1 {
                    self.isLoading = false
                    self.loadingMessage = nil
                }
                // Self-healing scrub guard: while the user is ACTIVELY scrubbing
                // (recent movement) the scrub owns currentPosition, so skip the
                // player's reported time. But if the gesture's .onEnded never
                // fired (cancelled by a sheet / track change / re-render) the
                // flag would latch and freeze the timer forever — so it expires
                // shortly after the last scrub movement.
                if self.isScrubbing {
                    if Date().timeIntervalSince(self.lastScrubActivity) < 0.6 { return }
                    self.isScrubbing = false
                }
                self.currentPosition = seconds
                self.trackDuration = self.audioPlayer.duration
                // (minTrackDuration is enforced invisibly in advanceToNext via
                // assetDuration pre-screening, before the track is revealed.)
                // Persist position so the user resumes EXACTLY where they were —
                // for every channel type (not just spoken-word) and playlists.
                // Throttled: write DB at most once every 5 s (timer fires 4×/s).
                if let track = self.currentTrack,
                   self.currentChannel?.contentType != .ambientLoop,
                   seconds - self.lastPositionSaveTime >= 5.0 {
                    self.lastPositionSaveTime = seconds
                    if let playlist = self.currentPlaylist {
                        await self.db.savePosition(
                            channelId: Self.playlistKey(playlist.id),
                            trackId: track.id, seconds: seconds)
                    } else if let channel = self.currentChannel {
                        await self.db.savePosition(
                            channelId: channel.id,
                            trackId: track.id, seconds: seconds)
                    }
                    self.persistSession(position: seconds)
                }
            }
        }

    }

    convenience init(deps: AppDependencies) {
        self.init(
            db: deps.db,
            archiveService: deps.archiveService,
            fmaService: deps.fmaService,
            queueManager: deps.queueManager,
            audioPlayer: deps.audioPlayer,
            downloadManager: deps.downloadManager
        )
    }

    // Set from the scrub gestures (wheel ring drag + progress slider). Stamps
    // the activity time so the self-healing guard in onTimeUpdate knows the
    // drag is still live; when set false it releases immediately.
    func setScrubbing(_ active: Bool) {
        if active { lastScrubActivity = Date() }
        if isScrubbing != active { isScrubbing = active }   // avoid redundant publishes
    }

    /// Persist the EXACT current spot for the active context. Call this whenever
    /// the user leaves the player (opens the menu, backgrounds the app) or
    /// pauses, so the resume marker is always the precise track + offset — never
    /// the stale throttled value or 0:00. Writes the context position
    /// (playlist/channel), the per-track autosave, and the global session.
    func saveCurrentSpot() {
        guard let track = currentTrack,
              currentChannel?.contentType != .ambientLoop else { return }
        let pos = currentPosition
        let trackId = track.id
        if let playlist = currentPlaylist {
            let key = Self.playlistKey(playlist.id)
            Task { [db] in await db.savePosition(channelId: key, trackId: trackId, seconds: pos) }
        } else if let channel = currentChannel {
            let cid = channel.id
            Task { [db] in await db.savePosition(channelId: cid, trackId: trackId, seconds: pos) }
        }
        saveAutosaveForCurrentTrack()
        persistSession(position: pos)
    }

    /// Called when Kids Mode is turning ON (mid-session, or while entering Kids
    /// Mode on launch). Clears `playHistory` so back-track can't reach
    /// pre-Kids-Mode tracks, and returns the channel the caller must load to
    /// redirect — or `nil` if the current context is already kid-safe (a
    /// children's channel or a kid-safe playlist). The single decision lives in
    /// `KidsModeController.needsRedirect`, which is unit-tested.
    func enterKidsMode() -> Channel? {
        playHistory = []
        let needs = KidsModeController.needsRedirect(
            currentChannelId: currentChannel?.id,
            currentPlaylistIsKidSafe: currentPlaylist?.isKidSafe)
        guard needs else { return nil }
        return KidsModeController.allowedChannels().first
    }

    /// DEBUG-only runtime check: while Kids Mode is on, the current context
    /// MUST be an allowed channel OR a kid-safe playlist. Any other state is a
    /// leak. Logs loud so manual TestFlight testing surfaces it; intentionally
    /// NOT an assertionFailure so an unrelated test that flips the singleton
    /// doesn't crash on this path.
    func assertKidsModeInvariant() {
        #if DEBUG
        guard KidsModeController.shared.isEnabled else { return }
        if !KidsModeController.invariantHolds(
            currentChannelId: currentChannel?.id,
            currentPlaylistIsKidSafe: currentPlaylist?.isKidSafe) {
            Log.playback.error("⚠️ Kids Mode invariant violated — channel=\(self.currentChannel?.id ?? "nil") playlist.isKidSafe=\(String(describing: self.currentPlaylist?.isKidSafe))")
        }
        #endif
    }

    func load(channel: Channel, autoPlay: Bool = true) async {
        // OFFLINE GUARD — the very first thing, BEFORE we stop the current audio.
        // If this channel needs the network, we're offline, and it has no
        // downloaded tracks, tell the user and leave whatever is playing (e.g. a
        // downloaded audiobook) completely untouched. Previously this path
        // timed out ~10 s, then silently advanced the still-current playlist to
        // the wrong track — destroying the user's resume point. (Ambient loops
        // are bundled, so they're never blocked.)
        if channel.contentType != .ambientLoop, !NetworkMonitor.shared.isOnline {
            let localCount = await db.offlineTrackCount(forChannel: channel)
            if localCount == 0 {
                transientMessage = "You're offline. Only downloaded playlists can be played without a connection."
                return
            }
        }

        // Safety-net autosave for the outgoing track (channel switch is one
        // of the "lose your spot" scenarios).
        saveAutosaveForCurrentTrack()
        // UC5: stop any currently playing audio immediately so old track doesn't bleed into new channel.
        audioPlayer.skip()
        currentTrack = nil
        isPlaying = false
        playHistory = []
        currentTrackIsMultiPart = false
        itemPartsCache = [:]   // IA item file lists are immutable per session
        // UC2: persist last-used channel so the app restores it after restart.
        UserDefaults.standard.set(channel.id, forKey: "lastChannelId")
        // UC6: track visited channels for Favorites (MRU, capped at 20).
        var visited = UserDefaults.standard.stringArray(forKey: "visitedChannelIds") ?? []
        visited.removeAll { $0 == channel.id }
        visited.insert(channel.id, at: 0)
        if visited.count > 20 { visited = Array(visited.prefix(20)) }
        UserDefaults.standard.set(visited, forKey: "visitedChannelIds")

        LorewaveIntentDonations.donateChannel(channel)
        if channel.category == "Podcasts" {
            LorewaveIntentDonations.donatePodcast(channel)
        }

        currentChannel = channel
        // New playback context → invalidate any track still resolving from the
        // previous context (see playbackContextToken).
        playbackContextToken &+= 1
        // Leave playlist mode NOW that we've committed to a channel. Doing this
        // here (not only on the fetch SUCCESS path) is critical: if the fetch
        // fails, advanceToNext must NOT see a stale currentPlaylist and advance
        // it to the wrong track (the lost-audiobook-spot bug).
        currentPlaylist = nil
        playlistTracks = []
        playlistIndex = 0
        // Clear the previous context's artwork/background IMMEDIATELY (before the
        // fetch await) so switching channels never lingers on the old album art.
        currentArtwork = nil
        artworkDominantColor = .accentColor
        // Shuffle is per-context: switching channels ALWAYS resets to NOT
        // shuffling, so an audiobook/lecture channel never inherits a shuffle
        // left on from a music channel or playlist.
        shuffleMode = false
        // Lock-screen controls follow the content: spoken-word channels get
        // ±15 s skip buttons; music channels get next/prev track.
        audioPlayer.setContentMode(channel.contentType == .spokenWord ? .spokenWord : .music)
        isLoading = true
        loadingMessage = "Finding tracks…"
        errorMessage = nil
        currentPosition = 0
        trackDuration = nil
        // Fresh channel the user explicitly chose → fresh stall + retry budget.
        stallModel.resetSkipStreak()
        loadAttempts.removeAll()

        // Hoisted so the post-fetch resume / News-newest logic can see it.
        var fetched: [Track] = []

        // INSTANT RESUME: for channels where the last-played track is always
        // cached in the DB (curated, audiobook, lecture), check the saved
        // position BEFORE hitting the network. If the track is in the DB and
        // still approved (curated), play it immediately without a loading
        // spinner. The IA query still runs in the background to refresh the
        // pool for subsequent tracks.
        let isInstantResumeCategory = channel.category == "Curated"
            || channel.category == "Audiobooks"
            || channel.category == "Lectures"
        if isInstantResumeCategory {
            if let saved = await db.loadPosition(channelId: channel.id),
               let track = await db.fetchTrack(id: saved.trackId) {
                // Curated channel: verify the track is still in the approved pool.
                // pool(for:) reads directly from the in-memory DB snapshot —
                // no JSON file fallback, so verdicts are always current.
                let approved = channel.category == "Curated"
                    ? Set(LiveCurationStore.shared.pool(for: channel.id).map(\.id))
                    : nil
                let isInstant = approved?.contains(track.id) ?? true
                if isInstant || approved?.isEmpty == true {
                    // Play instantly — no spinner, no waiting for the network
                    isLoading = false
                    loadingMessage = nil
                    if approved?.isEmpty == true {
                        // Channel has no approved tracks yet; skip the background
                        // fetch too — the user needs to curate first.
                        channelDescription = channel.detailDescription
                        return
                    }
                    // Play the cached track and launch a background refresh
                    await playTrack(track,
                                    seekTo: saved.seconds > 1 ? saved.seconds : nil,
                                    autoPlay: autoPlay)
                    // Background: fetch fresh tracks to update the pool while
                    // the user is already listening. This uses a separate context
                    // token so it doesn't interfere with the playing track.
                    let backgroundToken = playbackContextToken
                    Task.detached { [weak self] in
                        guard let self else { return }
                        await self.refreshChannelPool(channel: channel,
                                                       contextToken: backgroundToken)
                    }
                    return
                }
            }
        }

        do {
            if channel.category == "For You" {
                // Dynamic "for you" channels: build the query from listening
                // history at fetch time. If there isn't enough history yet, show
                // a friendly prompt and stop (no tracks to resume/advance into).
                if let built = try await fetchRecommendations(for: channel) {
                    fetched = built
                } else {
                    currentChannel = channel
                    channelDescription = channel.detailDescription
                    channelTrackCount = 0
                    currentArtwork = nil
                    currentTrack = nil
                    isPlaying = false
                    isLoading = false
                    loadingMessage = nil
                    errorMessage = "Listen to at least \(RecommendationQueryBuilder.minPlays) tracks first — then your \(channel.name) picks will appear here."
                    return
                }
            } else if channel.feedURL != nil {
                // News/podcast channels: fetch from RSS feed via PodcastRSSService.
                fetched = try await podcastService.fetchTracks(channel: channel)
            } else if channel.preferredSource == "nps" || channel.contentType == .ambientLoop {
                // Ambient static channels: hardcoded tracks, no network fetch needed.
                fetched = ambientService.fetchTracks(channel: channel)
            } else if channel.category == "Lectures" {
                // Oxford channels fetch from podcasts.ox.ac.uk via OxfordLecturesService.
                fetched = try await oxfordService.fetchTracks(unitSlug: channel.tags.first ?? "")
            } else if let entry = channel.iaQueryEntry {
                // Pure-Lucene registry channels (curated music + LibriVox
                // audiobooks) — checked BEFORE the spoken-word branch so
                // .spokenWord LibriVox channels use the registry query, not
                // the legacy fetchSpokenWordTracks path. matchTags stamp
                // isolates them in the shared DB; sort=random gives variety.
                let lang = channel.category == "Audiobooks" ? "eng" : nil
                fetched = try await archiveService.fetchTracks(
                    iaQuery: entry.iaQuery, matchTags: entry.matchTags,
                    language: lang
                )
            } else if channel.contentType == .spokenWord {
                // Spoken-word channels with no registry entry: legacy IA path.
                fetched = try await archiveService.fetchSpokenWordTracks(channel: channel)
            } else if channel.composers.isEmpty {
                // Tag channels: IA + FMA in parallel; FMA errors are non-fatal.
                async let iaTracks = archiveService.fetchTracks(tags: channel.tags, excludeTags: channel.excludeTags)
                let fmaTracks = (try? await fmaService.fetchTracks(forChannel: channel)) ?? []
                let iaResults = try await iaTracks
                var seen = Set<String>()
                fetched = (iaResults + fmaTracks).filter { seen.insert($0.id).inserted }
            } else {
                // Composer channels: IA + Musopen(IA) + FMA all in parallel.
                async let iaTracks = archiveService.fetchTracks(
                    composers: channel.composers,
                    instruments: channel.instruments
                )
                var supplemental: [Track] = []
                await withTaskGroup(of: [Track].self) { group in
                    for composer in channel.composers {
                        group.addTask { (try? await self.archiveService.fetchMusopenTracks(composer: composer)) ?? [] }
                    }
                    group.addTask { (try? await self.fmaService.fetchTracks(forChannel: channel)) ?? [] }
                    for await tracks in group { supplemental.append(contentsOf: tracks) }
                }
                let iaResults = try await iaTracks
                var seen = Set<String>()
                fetched = (iaResults + supplemental).filter { seen.insert($0.id).inserted }
            }

            await db.saveTracks(fetched)
            // Registry (iaQuery) channels carry a unique isolation stamp, so we
            // can safely prune any previously-stamped tracks this — possibly
            // updated/narrowed — query no longer returns. Downloads are kept.
            // This is the GENERAL fix for "an old/broader query's results linger
            // in the local DB and repeat forever": the pool can never outlive
            // the current query's definition. (Tag/composer channels are NOT
            // pruned — they share tracks across channels by subject/composer.)
            //
            // For Curated channels, the keeping set INCLUDES approved track IDs
            // even if the IA query no longer returns them. This prevents the
            // "lose 23 approved tracks" bug where PRUNE 1 deleted approved
            // tracks not in the query, then PRUNE 2 couldn't restore them.
            if channel.iaQueryEntry != nil, !fetched.isEmpty {
                var keepingIds = Set(fetched.map(\.id))
                if channel.category == "Curated" {
                    let approvedIds = LiveCurationStore.shared
                        .pool(for: channel.id).map(\.id)
                    keepingIds.formUnion(approvedIds)
                }
                await db.pruneChannelTracks(
                    forChannel: channel, keeping: keepingIds)
            }
            downloadManager.prefetchNext(fetched)
            channelDescription = channel.detailDescription
            channelTrackCount = fetched.count
            channelMostRecentDate = fetched.compactMap(\.addedDate).max()
        } catch let urlError as URLError
            where urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
            // Network dropped mid-fetch. Show the offline notice and STOP — do
            // NOT fall through to resume/advance (which would churn trying to
            // stream offline). currentPlaylist is already cleared, so nothing
            // gets clobbered.
            transientMessage = "You're offline. Only downloaded playlists can be played without a connection."
            isLoading = false
            loadingMessage = nil
            return
        } catch {
            errorMessage = "Couldn't load this channel. Please try again."
            isLoading = false
            loadingMessage = nil
            return
        }

        // Ambient loops: always play THIS channel's own bundled loop track so
        // the title/artwork are correct — never a stale saved position that
        // could point at a previously-played non-ambient track.
        if channel.contentType == .ambientLoop {
            if let amb = fetched.first {
                await playTrack(amb, seekTo: nil, autoPlay: autoPlay)
            }
            isLoading = false
            loadingMessage = nil
            return
        }

        let saved = await db.loadPosition(channelId: channel.id)

        // NEWS: on re-entry, if a NEWER episode than the one last played has
        // appeared in the feed, jump straight to the newest and play it,
        // ignoring the saved position. (News only; only when newer arrived.)
        if channel.feedURL != nil, !fetched.isEmpty {
            let newest = fetched.max {
                ($0.bestDate ?? .distantPast) < ($1.bestDate ?? .distantPast)
            }
            let savedTrack = saved.flatMap { s in
                fetched.first { $0.id == s.trackId }
            }
            let savedDate = savedTrack?.bestDate ?? .distantPast
            if let newest,
               newest.id != saved?.trackId,
               (newest.bestDate ?? .distantPast) > savedDate {
                await db.clearPosition(channelId: channel.id)
                await db.recordPlayed(channelId: channel.id, trackId: newest.id)
                loadingMessage = "Loading the latest…"
                await playTrack(newest, seekTo: nil, autoPlay: autoPlay)
                isLoading = false
                loadingMessage = nil
                return
            }
        }

        // Resume the last-played track for ALL channel types, at its exact
        // saved offset (the user asked to always pick up where they were).
        // autoPlay is threaded all the way into AudioPlayerService so a paused
        // resume still loads, seeks and shows its duration — it just doesn't
        // start — instead of the old race that left the track silent.
        if let saved, let track = await db.fetchTrack(id: saved.trackId),
           await resumeTrackBelongs(track, toChannel: channel) {
            loadingMessage = "Resuming \"\(track.title)\"…"
            await playTrack(track, seekTo: saved.seconds > 1 ? saved.seconds : nil,
                            autoPlay: autoPlay)
        } else {
            // No usable resume, OR the saved position points at a FOREIGN track
            // (e.g. a playlist book chapter an earlier bug wrote under this
            // channel's position — the "Classical Guitar played my book" bug).
            // Drop the bad marker so it can't hijack the channel again, and
            // start the channel fresh.
            if saved != nil { await db.clearPosition(channelId: channel.id) }
            loadingMessage = "Starting playback…"
            await advanceToNext(autoPlay: autoPlay)
        }

        // Don't clear isLoading here — playTrack/advanceToNext own the spinner
        // from this point and dismiss it on the first real time tick (or on
        // failure / give-up). Clearing here used to drop the spinner during
        // AVPlayer's pre-buffer window — visible on long audiobook resumes as
        // "no spinner is shown" even though audio hasn't started yet.
    }

    func togglePlayPause() {
        if audioPlayer.isPlaying {
            // Capture the EXACT spot BEFORE telling the player to pause — once
            // the user is paused the position will not advance, but if they exit
            // the app right after a pause we still want the latest offset saved
            // as the playlist/channel resume point.
            saveCurrentSpot()
            audioPlayer.pause()
            isPlaying = false
        } else if currentTrack != nil {
            audioPlayer.resume()
            isPlaying = true
        }
    }

    func skip() {
        // Ambient loops have exactly one track; forward just restarts it.
        if let channel = currentChannel, channel.contentType == .ambientLoop {
            audioPlayer.seek(to: 0)
            currentPosition = 0
            return
        }
        // Save autosave for the outgoing track — user pressed next, didn't
        // finish naturally, so their spot might still matter.
        saveAutosaveForCurrentTrack()
        isSkipping = true
        audioPlayer.skip()
        isPlaying = false
        currentPosition = 0
        // Show the spinner immediately (trackMetadataStack renders a
        // ProgressView while isLoading). currentTrack stays set so playlist
        // index + history math in advanceToNext stays correct.
        errorMessage = nil
        isLoading = true
        loadingMessage = "Loading…"
        if let channel = currentChannel, channel.contentType == .spokenWord {
            Task {
                await db.clearPosition(channelId: channel.id)
                await advanceToNext()
                isSkipping = false
            }
        } else {
            Task {
                await advanceToNext()
                isSkipping = false
            }
        }
    }

    func seek(to seconds: Double) {
        audioPlayer.seek(to: seconds)
        currentPosition = seconds
    }

    /// Relative seek within the track, clamped to [0, duration]. Used by the
    /// wheel's single-tap (±10 s) and press-and-hold scrub.
    func seekBy(_ delta: Double) {
        let target = max(0, currentPosition + delta)
        let cap = (trackDuration ?? 0) > 0 ? trackDuration : (currentTrack.map { $0.duration > 0 ? $0.duration : nil } ?? nil)
        seek(to: cap.map { min(target, $0) } ?? target)
    }

    /// Always jump to the previous track (the wheel's double-tap-back), using
    /// channel history or the playlist cursor — never just a restart-in-place
    /// unless there's genuinely nothing before the current track.
    func goToPreviousTrack() async {
        saveAutosaveForCurrentTrack()
        await playPreviousTrack()
    }

    func back() {
        // Uniform for all channel types: restart current track if well into it; previous track if near start.
        if currentPosition > 3 {
            audioPlayer.seek(to: 0)
            currentPosition = 0
        } else {
            saveAutosaveForCurrentTrack()
            Task { await playPreviousTrack() }
        }
    }

    // MARK: - Private

    /// Whether `track` legitimately belongs to `channel` as a resume target.
    /// REGISTRY channels isolate STRICTLY by their injected stamp, so a saved
    /// position pointing at a FOREIGN track — e.g. a playlist book chapter an
    /// earlier bug recorded under this channel's position — must be rejected so
    /// it can't hijack the channel. Book CHAPTERS are intentionally left
    /// unstamped, so a chapter belongs iff its parent ITEM is stamped for the
    /// channel (keeps legit audiobook-channel chapter resumes working).
    /// Non-registry channels (News / Lectures / Ambient) keep prior behavior —
    /// their matching is tag-based, not stamp-precise, so we don't risk
    /// clearing a good lecture/news resume.
    private func resumeTrackBelongs(_ track: Track, toChannel channel: Channel) async -> Bool {
        guard channel.iaQueryEntry != nil else { return true }
        // Stamp check: does the track carry this channel's isolation tag?
        let stamped = channel.matches(track)
        if !stamped {
            if let pid = track.parentIdentifier, !pid.isEmpty,
               let parent = await db.fetchTrack(id: pid) {
                guard channel.matches(parent) else { return false }
            } else { return false }
        }
        // Approval check: for Curated channels, the track must also be in the
        // human-approved pool. A stamped track from a prior load is not enough.
        if channel.category == "Curated" {
            let approvedIds = Set(LiveCurationStore.shared.pool(for: channel.id).map(\.id))
            guard !approvedIds.isEmpty, approvedIds.contains(track.id) else {
                return false
            }
        }
        return true
    }

    private func advanceToNext(autoPlay: Bool = true) async {
        // Playlist mode: advance within the playlist's ordered tracks.
        // (currentChannel is nil in playlist mode, so the channel queue path
        // below would otherwise do nothing — which is why <next> was dead.)
        if currentPlaylist != nil {
            await advancePlaylist()
            return
        }
        guard let channel = currentChannel else { return }

        // Record the OUTGOING track in channel history NOW, before any code
        // path (e.g. min-duration screening) nils currentTrack. This is what
        // makes double-tap-back reliably return the previous track instead of
        // a fresh random pick. Deduped + capped. Subsequent playTrack calls in
        // this method pass recordHistory:false so we don't double-record.
        if let outgoing = currentTrack {
            if playHistory.last?.id != outgoing.id {
                playHistory.append(outgoing)
                if playHistory.count > historyLimit { playHistory.removeFirst() }
            }
        }

        // Assert a background task so iOS doesn't kill the network call that
        // resolves the next track URL when the app is backgrounded.
        // nonisolated(unsafe): the expiration handler must see the real task
        // id, so it has to be captured-then-mutated. Begin/end and the handler
        // all run on the main actor, so the access is in fact serialized.
        nonisolated(unsafe) var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "advance-track") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        defer {
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }

        // Librivox sequential multi-part: advance to next part before random
        // pick. SPOKEN-WORD only — on a music channel a played album track has a
        // parentIdentifier too, but we want the NEXT skip to jump to a fresh
        // random album track, not march sequentially through one album.
        if channel.contentType == .spokenWord,
           let current = currentTrack, current.parentIdentifier != nil {
            if let nextPart = await queueManager.nextPart(after: current, channel: channel) {
                await playTrack(nextPart, seekTo: nil, recordHistory: false, autoPlay: autoPlay)
                return
            }
        }

        guard var track = await queueManager.nextTrack(channel: channel, shuffleMode: shuffleMode) else {
            currentTrack = nil
            isPlaying = false
            if errorMessage == nil {
                errorMessage = "No tracks found. Try refreshing or select another channel."
            }
            isLoading = false
            return
        }

        // minTrackDuration channels (Children's Songs): screen candidates by
        // their real duration BEFORE revealing anything. Too-short tracks stay
        // COMPLETELY invisible — the screen shows only the loading spinner
        // (currentTrack nil) until a track ≥ the minimum is found.
        if let minDur = channel.minTrackDuration {
            currentTrack = nil
            currentArtwork = nil
            isPlaying = false
            isLoading = true
            loadingMessage = "Finding a track…"
            var tries = 0
            while tries < maxConsecutiveLoadFailures {
                let d = await assetDuration(for: track)
                if let d, d >= minDur { break }
                tries += 1
                guard let next = await queueManager.nextTrack(
                    channel: channel, shuffleMode: shuffleMode) else { break }
                track = next
            }
        }
        // MUSIC albums: a multi-file item is an ALBUM — play a RANDOM track from
        // it, not always track 1 (the "only ever Part 1 of N" complaint). Over
        // repeated visits the whole album gets heard. Audiobooks/lectures
        // (spoken-word) keep playing the FIRST part on the channel; the user
        // adds the whole book to a playlist to hear it in order.
        if channel.contentType == .music {
            track = await randomAlbumTrack(for: track) ?? track
        }
        await playTrack(track, seekTo: nil, recordHistory: false, autoPlay: autoPlay)
    }

    /// If `track` is a known multi-file IA album item, return a RANDOM one of
    /// its tracks; otherwise nil (caller keeps the original). DELIBERATELY uses
    /// only ALREADY-KNOWN parts (in-session cache or the DB) — it never fires a
    /// fresh network probe, so it can't hang a skip (advanceToNext has no
    /// watchdog). probeCurrentTrack warms the cache + persists the parts to the
    /// DB after a play, so the first-ever play of an album is track 1 and every
    /// later visit (incl. future launches) gets a random track.
    private func randomAlbumTrack(for track: Track) async -> Track? {
        guard track.source == "internet_archive",
              track.parentIdentifier == nil,   // already a specific part → leave it
              !track.id.contains("/") else { return nil }
        if let cached = itemPartsCache[track.id] {       // key present → definitive
            guard let parts = cached, parts.count > 1 else { return nil }
            return parts.randomElement()
        }
        let dbParts = await db.fetchTracks(forParentIdentifier: track.id)
        guard dbParts.count > 1 else { return nil }
        return dbParts.randomElement()
    }

    // Resolve a track's playable URL and read its duration WITHOUT starting
    // audible playback (used to pre-screen min-duration channels silently).
    private func assetDuration(for track: Track) async -> Double? {
        let url: URL
        if track.id.contains("/") {
            url = track.streamURL
        } else if track.source == "internet_archive" {
            let svc = archiveService
            let identifier = track.id
            guard let resolved = try? await Self.withTimeout(loadTimeout, {
                try await svc.resolveAudioURL(for: identifier)
            }) else { return nil }
            url = resolved
        } else {
            url = track.streamURL
        }
        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration) else { return nil }
        let secs = CMTimeGetSeconds(dur)
        return secs.isFinite && secs > 0 ? secs : nil
    }

    private func advancePlaylist() async {
        guard !playlistTracks.isEmpty else { return }
        if shuffleMode, playlistTracks.count > 1 {
            var i = Int.random(in: 0..<playlistTracks.count)
            if i == playlistIndex { i = (i + 1) % playlistTracks.count }
            playlistIndex = i
        } else {
            playlistIndex = (playlistIndex + 1) % playlistTracks.count
        }
        // recordHistory:false — playlist back navigation uses the cursor.
        await playTrack(playlistTracks[playlistIndex], seekTo: nil, recordHistory: false)
    }

    private func playPreviousTrack() async {
        // Playlist mode: step backward through playlist order. The first track
        // restarts in place; never fall back to channel playHistory.
        if currentPlaylist != nil {
            guard !playlistTracks.isEmpty, playlistIndex > 0 else {
                // First track (or empty): restart in place; never fall back
                // to channel playHistory.
                audioPlayer.seek(to: 0)
                currentPosition = 0
                return
            }
            playlistIndex -= 1
            await playTrack(playlistTracks[playlistIndex], seekTo: nil, recordHistory: false)
            return
        }
        guard !playHistory.isEmpty else {
            // No history: restart the current track from the beginning.
            audioPlayer.seek(to: 0)
            currentPosition = 0
            return
        }
        let previous = playHistory.removeLast()
        await playTrack(previous, seekTo: nil, recordHistory: false)
    }

    private func playTrack(_ track: Track, seekTo: Double?, recordHistory: Bool = true,
                           autoPlay: Bool = true) async {
        // Snapshot the context this play was initiated under. If it changes
        // during the (awaited) URL resolution, we abandon before committing
        // audio so a stale track never plays under a context we've left.
        let entryToken = playbackContextToken
        // Hide the book/album buttons immediately; the probe re-enables them
        // once it confirms this track belongs to a multi-file item.
        currentTrackIsMultiPart = false
        currentItemChapterCount = 0
        currentItemTotalDuration = 0
        currentItemPartIndex = nil
        // UC3: push current track onto history before replacing it.
        if recordHistory, let existing = currentTrack {
            playHistory.append(existing)
            if playHistory.count > historyLimit { playHistory.removeFirst() }
        }
        // Defensive: a new track always starts un-scrubbed (a drag gesture
        // interrupted by a transition could otherwise leave this stuck true,
        // freezing the progress bar).
        isScrubbing = false
        // Reset the position-save throttle per track: it tracks the LAST track's
        // elapsed seconds, so without this a new track's early position wouldn't
        // be persisted until it passed the previous track's offset (leaving the
        // resume marker stuck at 0:00 if the user left early).
        lastPositionSaveTime = -5
        // New track → new watchdog generation; cancel any prior one. Capture
        // the generation: if ANOTHER playTrack starts while this one is still
        // resolving (rapid Back/Skip taps spawn concurrent loads), it bumps the
        // generation, and this stale load must abandon before committing audio —
        // otherwise two loads stomp each other's player/watchdog and the track
        // can end up shown but never playing, with no spinner (the rapid-Back bug).
        let loadGen = stallModel.beginLoad()
        stallWatchdog?.cancel()
        stallWatchdog = nil
        // Reload bookmarks for the new track (replaced below).
        bookmarksForCurrentTrack = []
        currentTrack = track
        Task { [weak self, id = track.id] in
            guard let self else { return }
            let bms = await self.db.fetchBookmarks(forTrack: id)
            await MainActor.run {
                if self.currentTrack?.id == id {
                    self.bookmarksForCurrentTrack = bms
                }
            }
        }
        // Pre-set duration from track metadata so scrubber renders before AVPlayer buffers.
        trackDuration = track.duration > 0 ? track.duration : nil
        // Clear the previous track's artwork IMMEDIATELY so a track with no
        // image never shows the prior track's picture. The procedural
        // visualizer fills the gap until/unless real art resolves.
        currentArtwork = nil
        artworkDominantColor = .accentColor
        // Load artwork asynchronously so playback starts without waiting.
        Task { [weak self] in
            guard let self else { return }
            let art = await ArtworkService.shared.bestArtwork(for: track, channel: currentChannel)
            // Stale-guard: a slow fetch for a track the user already skipped
            // past must NOT overwrite the current track's (cleared) artwork.
            guard self.currentTrack?.id == track.id else { return }
            self.currentArtwork = art
            if let art {
                let uiColor = ArtworkService.shared.dominantColor(from: art)
                self.artworkDominantColor = Color(uiColor)
                audioPlayer.updateNowPlayingArtwork(art)
            } else {
                self.artworkDominantColor = .accentColor
            }
        }
        isLoading = true
        loadingMessage = track.source == "internet_archive" ? "Buffering…" : "Loading…"

        do {
            let url: URL
            if track.isLocal || track.source == "local" {
                // Imported file — resolve against the CURRENT Documents dir
                // (a stored absolute sandbox path goes stale across launches).
                guard let local = track.resolvedLocalURL else {
                    throw URLError(.fileDoesNotExist)
                }
                url = local
            } else if let localPath = track.localFilePath,
                      FileManager.default.fileExists(atPath: localPath) {
                url = URL(fileURLWithPath: localPath)   // offline-downloaded track
            } else if (track.source != "internet_archive" || track.id.contains("/")),
                      case let downloaded = fileStorage.localURL(for: track.id),
                      FileManager.default.fileExists(atPath: downloaded.path) {
                // A genuinely-downloaded file on disk (per-file IA track, FMA,
                // imported) whose in-memory Track lacks localFilePath — play it
                // locally. CRUCIAL: this is GATED to per-file ids / non-IA. A
                // whole-item IA id ("identifier", no slash) has no direct file;
                // its only on-disk artifact is a prefetch of the item DIRECTORY
                // (a fake .mp3 that never plays). Those must always resolve.
                url = downloaded
            } else if track.source == "internet_archive" {
                if let cached = prefetchedURLs.removeValue(forKey: track.id) {
                    url = cached
                } else if track.id.contains("/") {
                    // Per-file track (id = "identifier/filename"): streamURL is
                    // already a direct download URL; resolveAudioURL with a
                    // slash-ID hits the wrong endpoint and would hang/throw.
                    url = track.streamURL
                } else {
                    // 10 s cap — many IA items have slow/huge metadata; without
                    // this the channel dead-ends on the first slow track.
                    let svc = archiveService
                    let identifier = track.id
                    url = try await Self.withTimeout(loadTimeout) {
                        try await svc.resolveAudioURL(for: identifier)
                    }
                }
            } else if currentChannel?.contentType == .ambientLoop,
                      let bundled = AmbientStaticService.bundledLoopURL(
                        forChannelId: currentChannel?.id ?? "") {
                // Offline + gapless: a committed local loop asset wins over
                // the streamed Freesound preview.
                url = bundled
            } else {
                url = track.streamURL
            }
            // Auto-resume from the safety-net autosave when no explicit
            // offset was provided AND we're not running an ambient loop.
            // This is what makes "never lose your spot" work across app
            // restarts and cross-channel listening.
            var effectiveSeek = seekTo ?? 0
            if seekTo == nil,
               currentChannel?.contentType != .ambientLoop,
               let auto = await db.fetchAutosaveBookmark(forTrack: track.id) {
                effectiveSeek = auto.positionSeconds
            }
            // News autoseek: skip introductory filler (see Channel.swift).
            // Only applies when no explicit seek/autosave, and not resuming.
            if seekTo == nil, effectiveSeek == 0,
               let offset = currentChannel?.startOffsetSeconds {
                effectiveSeek = offset
            }
            // Context changed (channel/playlist/search switch) OR a newer
            // playTrack superseded this one (rapid Back/Skip) → abandon before
            // committing audio. The winning load owns currentTrack/spinner.
            guard entryToken == playbackContextToken,
                  loadGen == stallModel.loadGeneration else { return }
            let resumeAt = max(effectiveSeek, 0)
            audioPlayer.play(url: url, track: track,
                             looping: currentChannel?.contentType == .ambientLoop,
                             startAt: resumeAt,
                             autoPlay: autoPlay)
            if let ch = currentChannel {
                audioPlayer.updateNowPlayingChannel(ch.name)
            }
            if let cachedArt = await ArtworkService.shared.cachedArtwork(for: track.id) {
                audioPlayer.updateNowPlayingArtwork(cachedArt)
            }
            if resumeAt > 0 {
                // Show the resume position in the UI immediately; AudioPlayer
                // applies the actual seek once the item is .readyToPlay.
                currentPosition = resumeAt
            }
            isPlaying = autoPlay
            errorMessage = nil
            failedAuditionTrackId = nil
            consecutiveLoadFailures = 0
            loadAttempts[track.id] = nil   // resolved/loaded OK → clear retry count
            assertKidsModeInvariant()      // DEBUG-only Kids Mode leak detector
            // Keep the loading indicator up until the player ACTUALLY produces
            // audio (the first periodic time tick clears it). Previously this
            // cleared the moment play() returned — seconds before sound. Ambient
            // loops start instantly from a bundled asset, so clear immediately.
            if currentChannel?.contentType == .ambientLoop {
                isLoading = false
                loadingMessage = nil
            } else {
                // Arm the buffering-stall watchdog for EVERY non-ambient track,
                // whether or not we intend to auto-play: if the item never even
                // becomes .readyToPlay (and never produces a tick) within
                // stallTimeout, it's stuck — skip to the next track so the
                // channel can't hang forever (this is the launch-after-update
                // "Buffering… forever, no timeout" bug). The skip preserves the
                // play intent so a paused launch stays paused on a working track.
                let gen = loadGen
                let timeout = stallTimeout
                let wantPlay = autoPlay
                stallWatchdog = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    await self?.handleStallIfNeeded(generation: gen, autoPlay: wantPlay)
                }
            }

            // Record EVERY real track in Recently Played — channels, playlists,
            // search picks, first-of-channel. (Ambient loops are excluded.)
            if currentChannel?.contentType != .ambientLoop {
                let ctx = currentChannel?.id
                    ?? currentPlaylist.map { Self.playlistKey($0.id) }
                    ?? "direct"
                let trackId = track.id
                Task { [db] in await db.recordPlayed(channelId: ctx, trackId: trackId) }
                // Engagement signal for the contribution prompt (never ambient).
                ContributionCoordinator.recordTrackPlayed()
            }

            if let channel = currentChannel {
                if channel.contentType != .spokenWord {
                    await db.savePosition(channelId: channel.id, trackId: track.id, seconds: 0)
                }
                Task { await prefetchNextURL(channel: channel) }
            } else if let playlist = currentPlaylist {
                // Record the playlist's current spot immediately on every
                // track change so Resume survives a force-quit (the throttled
                // onTimeUpdate save then keeps the offset fresh while playing).
                await db.savePosition(
                    channelId: Self.playlistKey(playlist.id),
                    trackId: track.id,
                    seconds: seekTo ?? 0
                )
            }
            // Persist the global session immediately so a relaunch right after
            // starting a track resumes exactly here.
            persistSession(position: resumeAt)
            probeCurrentTrack()
        } catch {
            await handleLoadFailure(track, error: error, autoPlay: autoPlay)
        }
    }

    // Buffering-stall watchdog handler. Fires stallTimeout after a track loaded.
    // The DECISION (stale / healthy / skip / give-up after too many consecutive
    // stalls with no audio) is made by the pure, unit-tested StallModel; the view
    // model only applies the verdict. See PLAYBACK-DESIGN.md.
    @MainActor
    func handleStallIfNeeded(generation: Int, autoPlay: Bool = true) async {
        guard currentChannel?.contentType != .ambientLoop else { return }
        switch stallModel.evaluateStall(generation: generation, autoPlay: autoPlay) {
        case .ignoreStale, .healthy:
            return
        case .giveUp:
            // Too many consecutive stalls with no audio in between — stop and tell
            // the user instead of buffering forever (the "infinite buffering" bug).
            stallModel.resetSkipStreak()
            stallWatchdog?.cancel()
            stallWatchdog = nil
            audioPlayer.skip()
            currentTrack = nil
            trackDuration = nil
            isPlaying = false
            isLoading = false
            loadingMessage = nil
            errorMessage = "Couldn't start playback — check your connection and try again."
        case .skip:
            Log.playback.error("Track stalled (no audio in \(self.stallTimeout)s) — skipping")
            audioPlayer.invalidateStreamingCache(for: currentTrack?.id ?? "")
            audioPlayer.skip()
            isPlaying = false
            currentPosition = 0
            errorMessage = nil
            // Audition context (no channel, no playlist) has nowhere to advance —
            // surface an error and CLEAR the spinner so it can't hang forever
            // (was: "Skipping unavailable track…" then advanceToNext returned
            // silently and isLoading stayed true — the curator-audition stuck-
            // spinner bug).
            if currentChannel == nil, currentPlaylist == nil {
                // Capture the failed track ID BEFORE clearing currentTrack so
                // curator views can identify which row failed (they check
                // failedAuditionTrackId in .onChange(of: errorMessage)).
                failedAuditionTrackId = currentTrack?.id
                currentTrack = nil
                trackDuration = nil
                isLoading = false
                loadingMessage = nil
                errorMessage = "Couldn't play this track — it may be unavailable or in an unsupported format."
                return
            }
            // Advance to the next track, keeping the original play intent so a
            // paused launch lands paused on a working track (not silently playing).
            isSkipping = true
            isLoading = true
            loadingMessage = "Skipping unavailable track…"
            await advanceToNext(autoPlay: autoPlay)
            isSkipping = false
        }
    }

    /// Stop any **audition-context** playback (no channel, no playlist active).
    /// Used by Curator Mode when the user exits the curator screen or
    /// backgrounds the app. No-op when current playback came from a real
    /// channel/playlist — we never disturb genuine listening.
    func stopAudition() {
        guard currentChannel == nil, currentPlaylist == nil,
              (currentTrack != nil || isLoading) else { return }
        stallWatchdog?.cancel()
        stallWatchdog = nil
        audioPlayer.skip()
        currentTrack = nil
        trackDuration = nil
        isPlaying = false
        isLoading = false
        loadingMessage = nil
        failedAuditionTrackId = nil
        errorMessage = nil
        playbackContextToken &+= 1   // invalidate any in-flight playTrack
        isAuditioning = false

        // Restore the pre-audition playback context so the user resumes
        // exactly where they were before entering curation / search.
        guard let pre = preAuditionState else { return }
        preAuditionState = nil
        currentChannel = pre.channel
        currentPlaylist = pre.playlist
        playlistTracks = pre.playlistTracks
        playlistIndex = pre.playlistIndex
        playHistory = pre.playHistory
        shuffleMode = pre.shuffleMode
        if let track = pre.track {
            Task {
                await playTrack(track, seekTo: pre.position > 1 ? pre.position : nil,
                                recordHistory: false, autoPlay: pre.isPlaying)
            }
        } else if let channel = pre.channel {
            Task { await load(channel: channel, autoPlay: pre.isPlaying) }
        } else if let playlist = pre.playlist {
            Task { await loadPlaylist(playlist, autoPlay: pre.isPlaying) }
        }
    }

    /// Stop audition playback WITHOUT restoring the pre-audition channel/
    /// playlist context. Use when a verdict was made on the playing track and
    /// the user expects silence — not the old channel resuming. Also used when
    /// the review queue is exhausted.
    func stopAuditionWithoutRestore() {
        guard currentChannel == nil, currentPlaylist == nil,
              (currentTrack != nil || isLoading) else { return }
        stallWatchdog?.cancel()
        stallWatchdog = nil
        audioPlayer.skip()
        currentTrack = nil
        trackDuration = nil
        isPlaying = false
        isLoading = false
        loadingMessage = nil
        failedAuditionTrackId = nil
        errorMessage = nil
        playbackContextToken &+= 1
        isAuditioning = false
        preAuditionState = nil
    }

    // MARK: - Whole book/album

    // Silent, async probe run at the end of playTrack. The button only
    // appears after it resolves; it never blocks playback or shows a spinner.
    private func probeCurrentTrack() {
        guard let track = currentTrack, track.source == "internet_archive" else {
            currentTrackIsMultiPart = false
            currentItemChapterCount = 0
            currentItemTotalDuration = 0
            currentItemPartIndex = nil
            return
        }
        let identifier = track.parentIdentifier ?? track.id
        Task { [weak self] in
            guard let self else { return }
            let parts = await self.resolveItemParts(identifier: identifier)
            // Stale-guard: the user may have skipped while the probe ran.
            guard self.currentTrack?.id == track.id ||
                  (track.parentIdentifier != nil &&
                   self.currentTrack?.parentIdentifier == track.parentIdentifier)
            else { return }
            self.currentTrackIsMultiPart = (parts != nil)
            guard let parts else {
                self.currentItemChapterCount = 0
                self.currentItemTotalDuration = 0
                self.currentItemPartIndex = nil
                return
            }
            self.currentItemChapterCount = parts.count
            self.currentItemTotalDuration = parts.reduce(0.0) { $0 + max(0, $1.duration) }
            // Which chapter is playing? The track's own part number wins; else
            // match by id; else an item-level entry resolves to the first file.
            if let pn = self.currentTrack?.partNumber {
                self.currentItemPartIndex = pn
            } else if let cur = self.currentTrack?.id,
                      let idx = parts.firstIndex(where: { $0.id == cur }) {
                self.currentItemPartIndex = idx + 1
            } else {
                self.currentItemPartIndex = 1
            }
        }
    }

    // The central probe/cache method. Returns nil for single-file items,
    // ordered parts for multi-file items. Network is hit at most once per
    // identifier across all sessions (verdict persisted in the DB).
    private func resolveItemParts(identifier: String) async -> [Track]? {
        // 1. In-session cache (key present → definitive; nil value = single).
        if let cached = itemPartsCache[identifier] { return cached }

        // 2. DB-first: already-expanded parts win — but ONLY if they form a
        //    clean single-format, contiguous set. Stale mixed-format rows from
        //    an older extraction are rejected so we re-probe and self-heal.
        let dbParts = await db.fetchTracks(forParentIdentifier: identifier)
        if dbParts.count >= 2, Self.partsAreClean(dbParts) {
            let ordered = dbParts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
            itemPartsCache[identifier] = ordered
            return ordered
        }

        // 3. Persisted single-file verdict on the item-level track.
        if let itemTrack = await db.fetchTrack(id: identifier),
           itemTrack.isMultiPart == false {
            itemPartsCache.updateValue(nil, forKey: identifier)
            return nil
        }

        // 4. Network probe (isMultiPart nil/true with parts evicted).
        do {
            let fetched = try await archiveService.fetchTracksForIdentifier(identifier)
            if fetched.count <= 1 {
                await db.setIsMultiPart(false, forTrackId: identifier)
                itemPartsCache.updateValue(nil, forKey: identifier)
                return nil
            }
            // Do NOT stamp probed chapters with the channel's matchTag: that
            // is what made every chapter join the channel pool, so skipping a
            // LibriVox channel cycled through one book's chapters. Unstamped
            // parts are still saved (retrievable by parent_identifier) and
            // added to playlists, but never match a channel → the channel
            // only ever offers the book's first track.
            await db.deleteTracks(forParentIdentifier: identifier)
            await db.saveTracks(fetched)
            await db.setIsMultiPart(true, forTrackId: identifier)
            let ordered = fetched.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
            itemPartsCache[identifier] = ordered
            return ordered
        } catch {
            // Network error: do NOT cache (absence = retry on next load).
            return nil
        }
    }

    // A DB part-set is trustworthy only if it is ONE audio format and its
    // part numbers are exactly 1…n (no gaps, dupes, or nils). Anything else
    // is a stale mixed-format extraction and must be re-probed.
    static func partsAreClean(_ parts: [Track]) -> Bool {
        guard !parts.isEmpty else { return false }
        let exts = Set(parts.map {
            ($0.id as NSString).pathExtension.lowercased()
        })
        guard exts.count == 1, exts.first?.isEmpty == false else { return false }
        let numbers = parts.compactMap(\.partNumber).sorted()
        return numbers.count == parts.count && numbers == Array(1...parts.count)
    }

    // "Add Entire Book/Album to Playlist" — adds every part in book/album
    // order. playlistVM is passed in (no stored reference) to keep the view
    // models decoupled and avoid a retain cycle.
    func addEntireItemToPlaylist(
        from track: Track, to playlist: Playlist, using playlistVM: PlaylistViewModel
    ) async {
        let identifier = track.parentIdentifier ?? track.id
        guard let parts = await resolveItemParts(identifier: identifier),
              !parts.isEmpty else { return }
        let ordered = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        await playlistVM.addTracks(ordered, to: playlist)
    }

    /// Play the CURRENT track's whole item (album / book) as a transient
    /// playlist queue — in order, or SHUFFLED when `shuffleMode` is on. Track
    /// Info's "Play Entire Album/Book" calls this. Leaves the channel context
    /// so the album owns playback; advancePlaylist walks the parts.
    func playEntireCurrentItem() async {
        guard let track = currentTrack else { return }
        let identifier = track.parentIdentifier ?? track.id
        guard let parts = await resolveItemParts(identifier: identifier),
              !parts.isEmpty else { return }
        let ordered: [Track]
        if shuffleMode, parts.count > 1 {
            ordered = parts.shuffled()
        } else {
            ordered = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        }
        saveAutosaveForCurrentTrack()
        // Build a transient (non-persisted) album playlist. The id is prefixed
        // "album:" so any saved-position writes don't collide with real
        // playlists. Bump the context token so prior in-flight loads bail.
        let albumPlaylist = Playlist(
            id: "album:\(identifier)",
            name: itemDisplayName(for: track),
            createdAt: Date(),
            updatedAt: Date(),
            isFavorites: false,
            isKidSafe: false
        )
        currentChannel = nil
        currentPlaylist = albumPlaylist
        playlistTracks = ordered
        playlistIndex = 0
        playbackContextToken &+= 1
        playHistory = []
        await playTrack(ordered[0], seekTo: nil, recordHistory: false)
    }

    // One-tap: create a playlist named after the book/album and add every
    // part to it in order. Smoother than the picker for a fresh shelf.
    @discardableResult
    func addEntireItemToNewPlaylist(
        from track: Track, named rawName: String, using playlistVM: PlaylistViewModel
    ) async -> Playlist? {
        let identifier = track.parentIdentifier ?? track.id
        guard let parts = await resolveItemParts(identifier: identifier),
              !parts.isEmpty else { return nil }
        let ordered = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = await playlistVM.createPlaylist(
            name: trimmed.isEmpty ? "New Playlist" : trimmed)
        await playlistVM.addTracks(ordered, to: playlist)
        return playlist
    }

    // Friendly book/album name for a part track: the IA item id prettified
    // (underscores/dashes → spaces, capitalised), else the track title.
    func itemDisplayName(for track: Track) -> String {
        guard let parent = track.parentIdentifier, !parent.isEmpty else {
            return track.title
        }
        let pretty = parent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return pretty.isEmpty ? track.title : pretty.capitalized
    }

    // Runs `op` but throws if it doesn't finish within `seconds`. nonisolated
    // static so it can also bound network work from inside a TaskGroup (the
    // recommendation fetch) without hopping back to the main actor.
    nonisolated static func withTimeout<T: Sendable>(
        _ seconds: Double, _ op: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw URLError(.timedOut) }
            return result
        }
    }

    private func classify(_ error: Error) -> PlaybackFailure {
        if let u = error as? URLError {
            return PlaybackFailureClassifier.classify(urlError: u.code)
        }
        return .transient   // resolve timeouts (withTimeout) / unknown → worth a retry
    }

    // Resolve/load failure. TRANSIENT failures (timeout, 5xx, connection lost)
    // retry the SAME track with exponential backoff before skipping; PERMANENT
    // ones (404/unsupported) skip immediately. When retries are exhausted we
    // advance to the next track, capped so a fully-dead channel stops cleanly.
    // Retry/backoff/classification are the pure, unit-tested policy core.
    private func handleLoadFailure(_ track: Track, error: Error, autoPlay: Bool) async {
        // Offline → retrying the network is pointless; treat as permanent so we
        // skip straight to the next (likely downloaded) track instead of burning
        // the backoff budget. Keeps offline playlist playback snappy.
        let failure: PlaybackFailure = NetworkMonitor.shared.isOnline ? classify(error) : .permanent
        let attempt = loadAttempts[track.id, default: 0]
        if retryPolicy.shouldRetry(afterAttempt: attempt, failure: failure) {
            loadAttempts[track.id] = attempt + 1
            let gen = stallModel.loadGeneration
            let delay = retryPolicy.delay(forAttempt: attempt, rand: Double.random(in: 0..<1))
            isLoading = true
            loadingMessage = "Reconnecting…"
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            // If the user changed channel/track during the backoff, a new load
            // bumped the generation — abort this stale retry.
            guard gen == stallModel.loadGeneration, !Task.isCancelled else { return }
            await playTrack(track, seekTo: nil, recordHistory: false, autoPlay: autoPlay)
            return
        }
        // Permanent, or out of retries for this item → give up on it.
        loadAttempts[track.id] = nil
        // Invalidate the streaming cache for this track so a re-visit starts
        // fresh (avoids "spins forever on re-visit" from a partial/corrupted cache).
        audioPlayer.invalidateStreamingCache(for: track.id)
        // A one-off play with no channel/playlist to advance within (a tapped
        // search result) has nowhere to go — advanceToNext would return doing
        // NOTHING, stranding the user on a silent, spinner-less screen (item 9).
        // Surface a clear error instead.
        if currentChannel == nil, currentPlaylist == nil {
            // Capture the failed track ID BEFORE clearing currentTrack so
            // curator views can show the yellow warning icon on the correct row.
            failedAuditionTrackId = currentTrack?.id
            currentTrack = nil
            trackDuration = nil
            isPlaying = false
            isLoading = false
            loadingMessage = nil
            // Distinguish the reason so the curator knows what to fix.
            if let urlError = error as? URLError {
                switch urlError.code {
                case .unsupportedURL:
                    errorMessage = "No playable audio file found on this IA item."
                case .timedOut:
                    errorMessage = "Timed out looking for playable audio — server may be slow."
                default:
                    errorMessage = "Couldn't play this track. It may be unavailable — try another."
                }
            } else {
                errorMessage = "Couldn't play this track. It may be unavailable — try another."
            }
            return
        }
        consecutiveLoadFailures += 1
        guard consecutiveLoadFailures < maxConsecutiveLoadFailures else {
            consecutiveLoadFailures = 0
            currentTrack = nil
            trackDuration = nil
            isPlaying = false
            isLoading = false
            loadingMessage = nil
            errorMessage = "Couldn't find a playable track in this channel."
            return
        }
        // Keep the spinner up and move on. currentTrack = nil so the failed
        // track isn't pushed onto playHistory by the next playTrack.
        currentTrack = nil
        trackDuration = nil
        isPlaying = false
        isLoading = true
        loadingMessage = "Skipping unavailable track…"
        await advanceToNext(autoPlay: autoPlay)
    }

    /// Background refresh: fetch updated tracks for a curated/audiobook/lecture
    /// channel while the user is already listening to the instantly-resumed
    /// cached track. Does NOT modify currentTrack or playback state — only
    /// updates the DB pool.
    private func refreshChannelPool(channel: Channel, contextToken: Int) async {
        var fetched: [Track] = []
        do {
            if let entry = channel.iaQueryEntry {
                let lang = channel.category == "Audiobooks" ? "eng" : nil
                fetched = try await archiveService.fetchTracks(
                    iaQuery: entry.iaQuery, matchTags: entry.matchTags,
                    language: lang)
            } else if channel.contentType == .spokenWord {
                fetched = try await archiveService.fetchSpokenWordTracks(channel: channel)
            }
            guard !fetched.isEmpty, contextToken == playbackContextToken else { return }
            await db.saveTracks(fetched)
            // Prune stale stamped tracks, keeping approved IDs for Curated channels
            var keepingIds = Set(fetched.map(\.id))
            if channel.category == "Curated", channel.iaQueryEntry != nil {
                let approvedIds = LiveCurationStore.shared
                    .pool(for: channel.id).map(\.id)
                keepingIds.formUnion(approvedIds)
            }
            await db.pruneChannelTracks(forChannel: channel,
                                         keeping: keepingIds)
            downloadManager.prefetchNext(fetched)
            channelTrackCount = fetched.count
            channelMostRecentDate = fetched.compactMap(\.addedDate).max()
        } catch { /* background refresh failure is silent — user is already playing */ }
    }

    private func prefetchNextURL(channel: Channel) async {
        guard let next = await queueManager.peekNextTrack(channel: channel, shuffleMode: shuffleMode),
              next.source == "internet_archive",
              prefetchedURLs[next.id] == nil else { return }
        if let url = try? await archiveService.resolveAudioURL(for: next.id) {
            prefetchedURLs[next.id] = url
        }
    }

    // MARK: - Shuffle and Repeat

    func toggleShuffle() {
        shuffleMode.toggle()
        UserDefaults.standard.set(shuffleMode, forKey: "shuffleMode")
    }

    func toggleRepeat() {
        repeatMode = repeatMode == .off ? .one : .off
        audioPlayer.repeatMode = repeatMode
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
    }

    // MARK: - Playlist playback

    // Synchronously wipe the outgoing track's UI state BEFORE any await, so
    // entering the main screen never shows stale elapsed time / artwork.
    // If `pre` is known, pre-populate it so its metadata shows under the
    // spinner; playTrack then finalises + starts audio in one update.
    private func beginTransition(pre: Track?) {
        audioPlayer.skip()
        currentArtwork = nil
        artworkDominantColor = .accentColor
        currentPosition = 0
        errorMessage = nil
        failedAuditionTrackId = nil
        isPlaying = false
        currentTrack = pre
        trackDuration = (pre?.duration ?? 0) > 0 ? pre?.duration : nil
        isLoading = true
        loadingMessage = "Loading…"
    }

    /// Audition a candidate from Curator Mode: play this exact track once,
    /// outside any channel / playlist context (the curator's verdict isn't
    /// playback, so no history / position recording is wanted).
    func auditionTrack(_ track: Track) async {
        // Only snapshot the pre-audition context ONCE — on the first track the
        // curator plays. Subsequent auto-advances within the same curation session
        // must NOT overwrite the snapshot, otherwise stopAudition() restores
        // (nil, nil, ...) instead of the original channel/playlist context.
        if !isAuditioning {
            preAuditionState = (
                channel: currentChannel, playlist: currentPlaylist,
                playlistTracks: playlistTracks, playlistIndex: playlistIndex,
                playHistory: playHistory, shuffleMode: shuffleMode,
                track: currentTrack, position: currentPosition, isPlaying: isPlaying
            )
        }
        isAuditioning = true
        currentChannel = nil
        currentPlaylist = nil
        playlistTracks = []
        playlistIndex = 0
        playbackContextToken &+= 1
        playHistory = []
        channelDescription = ""
        beginTransition(pre: track)
        await playTrack(track, seekTo: nil, recordHistory: false)
    }

    // Play a single Internet Archive search result immediately.
    func playSearchResult(_ group: SearchViewModel.ResultGroup) async {
        let pre = Track(
            id: group.id, source: "internet_archive",
            title: group.title, artist: group.creator,
            duration: group.duration,
            streamURL: URL(string: "https://archive.org/download/\(group.id)")
                ?? URL(string: "https://archive.org")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1.0, rawCreator: group.creator, composer: nil,
            instruments: [], metadataConfidence: 0.0,
            addedDate: group.addedDate
        )
        currentChannel = nil
        currentPlaylist = nil
        playlistTracks = []
        playlistIndex = 0
        playbackContextToken &+= 1   // new context (see playbackContextToken)
        playHistory = []
        channelDescription = ""
        beginTransition(pre: pre)
        await playTrack(pre, seekTo: nil, recordHistory: false)
        // NOTE: do NOT clear isLoading here — playTrack owns the spinner and
        // dismisses it on the first real time tick (or on failure). Clearing it
        // the instant playTrack returns dropped the spinner during AVPlayer's
        // pre-buffer window, so a tapped search result showed its name with no
        // spinner and no audio yet (item 9).
    }

    // Per-playlist position is stored in the same positions table as
    // channels, namespaced so it can never collide with a real channel id
    // (channel ids contain no ':').
    static func playlistKey(_ playlistId: String) -> String { "playlist:\(playlistId)" }

    func loadPlaylist(_ playlist: Playlist,
                       startingAt track: Track? = nil,
                       seekTo: Double = 0,
                       shuffle: Bool = false,
                       autoPlay: Bool = true) async {
        // Save the outgoing track's spot before switching context.
        saveAutosaveForCurrentTrack()
        // Shuffle is per-context: a normal play/resume resets it OFF; only the
        // Shuffle action turns it on. Prevents a stray shuffle from scrambling
        // an audiobook playlist's chapter order.
        shuffleMode = shuffle
        beginTransition(pre: track)
        currentPlaylist = playlist
        currentChannel = nil
        playbackContextToken &+= 1   // new context (see playbackContextToken)
        playHistory = []
        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        playlistTracks = tracks
        channelDescription = playlist.name
        channelTrackCount = tracks.count
        channelMostRecentDate = tracks.compactMap(\.addedDate).max()
        guard !tracks.isEmpty else { playlistIndex = 0; return }
        let startTrack = track ?? tracks.first!
        playlistIndex = track
            .flatMap { t in tracks.firstIndex(where: { $0.id == t.id }) } ?? 0
        // recordHistory:false — currentTrack here is still the previously-playing
        // CHANNEL track. Pushing it into playHistory is exactly why "back" on the
        // first playlist track used to jump to a track not in the playlist.
        await playTrack(startTrack, seekTo: seekTo, recordHistory: false, autoPlay: autoPlay)
    }

    // The saved spot in a playlist (track still present + offset), or nil.
    func savedPlaylistResume(_ playlist: Playlist) async -> (track: Track, seconds: Double)? {
        guard let saved = await db.loadPosition(channelId: Self.playlistKey(playlist.id))
        else { return nil }
        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        guard let track = tracks.first(where: { $0.id == saved.trackId }) else { return nil }
        return (track, saved.seconds)
    }

    // Shuffle: start on a RANDOM track and continue in random order (advance
    // already picks randomly while shuffleMode is on). Previously this called
    // loadPlaylist, which always started on the first track.
    func shufflePlaylist(_ playlist: Playlist) async {
        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        await loadPlaylist(playlist, startingAt: tracks.randomElement(), shuffle: true)
    }

    // Resume a playlist exactly where the user left off (the saved track at
    // its saved offset). Falls back to a normal play-from-top if nothing saved.
    func resumePlaylist(_ playlist: Playlist, autoPlay: Bool = true) async {
        if let resume = await savedPlaylistResume(playlist) {
            await loadPlaylist(playlist, startingAt: resume.track, seekTo: resume.seconds,
                               autoPlay: autoPlay)
        } else {
            await loadPlaylist(playlist, autoPlay: autoPlay)
        }
    }

    // MARK: - Book navigation (Librivox)

    func skipToNextBook() async {
        guard let channel = currentChannel, let current = currentTrack else { return }
        if let first = await queueManager.firstPartOfNextBook(after: current, channel: channel) {
            await playTrack(first, seekTo: 0, recordHistory: true)
        }
    }

    func skipToPreviousBook() async {
        guard let channel = currentChannel, let current = currentTrack else { return }
        if let first = await queueManager.firstPartOfPreviousBook(before: current, channel: channel) {
            await playTrack(first, seekTo: 0, recordHistory: true)
        }
    }

    // MARK: - Variable playback speed

    /// Allowed values for the speed picker (0.5×–2×).
    static let playbackRateOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    func setPlaybackRate(_ rate: Double) {
        let clamped = min(max(rate, 0.5), 2.0)
        playbackRate = clamped
        audioPlayer.setPlaybackRate(Float(clamped))
    }

    // MARK: - Sleep timer

    /// Start a countdown that pauses playback after `minutes` minutes. Replaces
    /// any active timer. `0` cancels.
    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard minutes > 0 else { return }
        let endsAt = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        sleepTimerEndsAt = endsAt
        sleepTimerTask = Task { [weak self] in
            let interval = endsAt.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.audioPlayer.pause()
                self.isPlaying = false
                self.sleepTimerEndsAt = nil
                self.sleepTimerTask = nil
            }
        }
    }

    /// Schedule a pause at the natural end of the currently-playing track.
    /// Replaces any countdown-based timer.
    func setSleepAtEndOfTrack(_ on: Bool) {
        cancelSleepTimer()
        sleepAtEndOfTrack = on
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEndsAt = nil
        sleepAtEndOfTrack = false
    }

    /// True iff any sleep mode is engaged.
    var isSleepTimerActive: Bool {
        sleepTimerEndsAt != nil || sleepAtEndOfTrack
    }

    // MARK: - Bookmarks

    /// Bookmark the current playback position. No-op if nothing's playing.
    func addBookmarkAtCurrentPosition(label: String? = nil) async {
        guard let track = currentTrack else { return }
        let bm = Bookmark.new(trackId: track.id,
                              positionSeconds: currentPosition,
                              label: label)
        await db.saveBookmark(bm)
        bookmarksForCurrentTrack = await db.fetchBookmarks(forTrack: track.id)
    }

    func deleteBookmark(_ bookmark: Bookmark) async {
        await db.deleteBookmark(id: bookmark.id)
        if let id = currentTrack?.id, id == bookmark.trackId {
            bookmarksForCurrentTrack = await db.fetchBookmarks(forTrack: id)
        }
    }

    /// Seek to a bookmarked position within the currently-playing track.
    func seekToBookmark(_ bookmark: Bookmark) {
        guard currentTrack?.id == bookmark.trackId else { return }
        seek(to: bookmark.positionSeconds)
    }

    // MARK: - Recently played

    func recentlyPlayedTracks(limit: Int = 30) async -> [Track] {
        await db.fetchRecentlyPlayedTracks(limit: limit)
    }

    /// Play a track straight from the Recently Played list. Looks up the
    /// last channel it was played in so the rotation context matches.
    func playRecentTrack(_ track: Track) async {
        await playTrack(track, seekTo: nil)
    }

    /// Remove a single track from Recently Played (every channel it was
    /// played in). The track itself stays in the local DB for playback.
    func removeFromRecentlyPlayed(_ track: Track) async {
        await db.deletePlayHistory(trackId: track.id)
    }

    /// Clear the entire Recently Played list.
    func clearRecentlyPlayed() async {
        await db.clearAllPlayHistory()
    }

    /// Settings → "Clear Listening History": wipe the all-time play history that
    /// powers the "for you" recommendation channels (and the Recently Played
    /// view, which is a window onto the same data). Playlists/downloads kept.
    func clearListeningHistory() async {
        await db.clearAllPlayHistory()
    }

    /// Build the track list for a "for you" channel from listening history.
    /// "Curated for you": sample tracks from the curated channels the user
    /// actually plays, weighted by how much they play each. No metadata
    /// fishing across all of IA (which used to leak 78rpm / amateur into the
    /// pool). Returns nil when there isn't enough qualifying history yet —
    /// caller shows the "listen to N tracks first" prompt.
    private func fetchRecommendations(for channel: Channel) async throws -> [Track]? {
        let history = await db.fetchRecentlyPlayedWithChannel(limit: 200)
        let catById = Dictionary(Channel.defaults.map { ($0.id, $0.category) },
                                 uniquingKeysWith: { a, _ in a })
        let isBooks = channel.id == "books-for-you"
        // ONLY count plays from the user's actual curated/audiobook channels —
        // For You, Ambient, News, Lectures, playlists are excluded so the
        // recommendations stay tightly within the wedge.
        let relevantCats: Set<String> = isBooks ? ["Audiobooks"] : ["Curated"]
        let relevantPlays = history.filter { relevantCats.contains(catById[$0.channelId] ?? "") }
        guard relevantPlays.count >= RecommendationQueryBuilder.minPlays else { return nil }

        let weights = RecommendationQueryBuilder.channelWeights(
            fromHistory: history, categoryFilter: relevantCats, categoryById: catById)
        let allocations = RecommendationQueryBuilder.allocateSamples(weights: weights)
        guard !allocations.isEmpty else { return nil }

        // Fetch each contributing channel's NATIVE registry query in parallel.
        // Stamp every fetched track with the For-You channel id so the DB
        // isolates them in the music-for-you / books-for-you pool.
        let svc = archiveService
        let stampTags = [channel.id]
        var pool: [Track] = []
        await withTaskGroup(of: [Track].self) { group in
            for (channelId, count) in allocations {
                guard let source = Channel.defaults.first(where: { $0.id == channelId }),
                      let entry = source.iaQueryEntry else { continue }
                group.addTask {
                    // Bound each query: a single slow IA response must not hang
                    // the whole "for you" build (the group waits for ALL tasks),
                    // which left Music/Books For You spinning ~60s with no track.
                    let tracks = (try? await Self.withTimeout(15) {
                        try await svc.fetchTracks(
                            iaQuery: entry.iaQuery, matchTags: stampTags)
                    }) ?? []
                    return Array(tracks.shuffled().prefix(count))
                }
            }
            for await tracks in group { pool.append(contentsOf: tracks) }
        }

        // Recommend NEW material only — drop anything already in the history,
        // and dedupe across channel overlaps.
        let playedIds = Set(history.map(\.track.id))
        var seen = Set<String>()
        return pool.filter { !playedIds.contains($0.id) && seen.insert($0.id).inserted }
    }

    /// Settings → "Clear All Data": stop playback and erase EVERYTHING — tracks,
    /// positions, playlists, play history, bookmarks (DB), plus the persisted
    /// session/preferences in UserDefaults. The caller also wipes downloaded
    /// files (OfflineDownloadService) and reloads playlists.
    func clearAllUserData() async {
        stallWatchdog?.cancel()
        audioPlayer.skip()
        currentTrack = nil
        isPlaying = false
        currentPlaylist = nil
        playlistTracks = []
        playHistory = []
        currentPosition = 0
        trackDuration = nil
        await db.wipeAllData()
        let d = UserDefaults.standard
        for k in ["session.kind", "session.contextId", "session.trackId",
                  "session.position", "lastChannelId", "visitedChannelIds",
                  "searchHistory", "shuffleMode", "wasPlayingOnQuit"] {
            d.removeObject(forKey: k)
        }
    }

    // MARK: - Chapters (multi-part items)

    /// Ordered chapters of the currently-playing multi-part item, or nil if
    /// the current item is single-file or there's nothing playing.
    func fetchCurrentItemChapters() async -> [Track]? {
        guard let track = currentTrack else { return nil }
        let identifier = track.parentIdentifier ?? track.id
        return await resolveItemParts(identifier: identifier)
    }

    // MARK: - Autosave bookmark (never lose position)

    /// Write the safety-net autosave for the currently-playing track.
    /// Fires-and-forgets a DB write so the call site stays synchronous.
    /// No-op when: nothing is playing, it's an ambient loop, the user has
    /// barely started (<5 s), or they're within 5 s of the end (a natural
    /// finish is about to delete it anyway).
    func saveAutosaveForCurrentTrack() {
        guard let track = currentTrack else { return }
        guard currentChannel?.contentType != .ambientLoop else { return }
        let pos = currentPosition
        guard pos > 5 else { return }
        // Prefer the live AVPlayer duration (accurate after readyToPlay); fall
        // back to the Track's stored duration when the player hasn't reported
        // one yet (tests, very first playTrack call, etc.).
        let dur = (trackDuration ?? 0) > 0 ? (trackDuration ?? 0) : track.duration
        if dur > 0, pos > dur - 5 { return }
        let trackId = track.id
        Task { [db] in
            await db.saveAutosaveBookmark(trackId: trackId, positionSeconds: pos)
        }
    }

    /// Delete the autosave for `trackId` (e.g. on natural completion).
    func deleteAutosaveForTrack(_ trackId: String) {
        Task { [db] in
            await db.deleteAutosaveBookmark(forTrack: trackId)
        }
    }

    /// Lookup helper for playTrack — returns the autosave offset if any.
    func autosavePosition(forTrack trackId: String) async -> Double? {
        await db.fetchAutosaveBookmark(forTrack: trackId)?.positionSeconds
    }

    // MARK: - Session restore (always pick up where you were)

    // Channel ids that were renamed/rebuilt; restore maps the old saved id to
    // the new. The guitar channel was rebuilt under a fresh id to shed stale
    // stamped tracks, so both prior ids forward to it.
    static let channelIdMigrations: [String: String] = [
        "classical-guitar": "guitar-classical",
        "spanish-guitar": "guitar-classical"
    ]

    static func migratedChannelId(_ id: String?) -> String? {
        guard let id else { return nil }
        return channelIdMigrations[id] ?? id
    }

    /// Persist the full "where I was": context (channel/playlist), track and
    /// offset. Called on every track start, on pause, on background, and
    /// throttled during playback — so a relaunch (incl. post-update) resumes
    /// exactly here.
    func persistSession(position: Double) {
        let d = UserDefaults.standard
        guard let track = currentTrack,
              currentChannel?.contentType != .ambientLoop else { return }
        guard !isAuditioning else { return }
        if let pl = currentPlaylist {
            d.set("playlist", forKey: "session.kind")
            d.set(pl.id, forKey: "session.contextId")
        } else if let ch = currentChannel {
            d.set("channel", forKey: "session.kind")
            d.set(ch.id, forKey: "session.contextId")
        } else {
            d.set("track", forKey: "session.kind")
            d.removeObject(forKey: "session.contextId")
        }
        d.set(track.id, forKey: "session.trackId")
        d.set(position, forKey: "session.position")
    }

    /// Restore the last session on launch. Channel/playlist resume uses the
    /// positions table; a globally-saved exact track wins if it differs (covers
    /// a last-played search result). autoPlay decides whether to start paused.
    func restoreLastSession(fallbackChannel: Channel, autoPlay: Bool) async {
        let d = UserDefaults.standard
        let kind = d.string(forKey: "session.kind")
        let contextId = d.string(forKey: "session.contextId")
        let savedTrackId = d.string(forKey: "session.trackId")
        let savedPosition = d.double(forKey: "session.position")

        if kind == "playlist", let pid = contextId,
           let pl = await db.fetchPlaylists().first(where: { $0.id == pid }) {
            await resumePlaylist(pl, autoPlay: autoPlay)
            // The DB position write is async fire-and-forget and can be LOST when
            // iOS kills the app in the background; session.position (UserDefaults,
            // written synchronously on pause/resign) is the durable record. If
            // it's for the SAME resumed track but AHEAD of the DB offset the
            // playlist restored from, jump to the real last spot — otherwise we'd
            // snap back to a stale "previous resume point" (the reported bug).
            if let cur = currentTrack, cur.id == savedTrackId,
               savedPosition > currentPosition + 2 {
                await playTrack(cur, seekTo: savedPosition,
                                recordHistory: false, autoPlay: autoPlay)
            }
            return
        }

        // Channel context (default). Migrate any renamed id; fall back to the
        // last-used channel from UserDefaults or the provided default.
        let channelId = Self.migratedChannelId(
            kind == "channel" ? contextId
                : (Self.migratedChannelId(d.string(forKey: "lastChannelId"))))
        let channel = Channel.defaults.first { $0.id == channelId } ?? fallbackChannel
        await load(channel: channel, autoPlay: autoPlay)

        if let tid = savedTrackId, let t = await db.fetchTrack(id: tid),
           NetworkMonitor.shared.isOnline || t.localFilePath != nil {
            // For Curated channels, verify the session-saved track is still
            // approved. A track that was once playable may have been rejected
            // since the last session.
            let isCurated = channel.category == "Curated" && channel.iaQueryEntry != nil
            let approved = isCurated
                ? Set(LiveCurationStore.shared.pool(for: channel.id).map(\.id))
                : nil
            if isCurated, let approved, !approved.isEmpty, !approved.contains(tid) {
                // Track was rejected or removed since last session — skip
            } else if currentTrack?.id != tid {
                // The exact last track differs from what the channel resumed
                // (e.g. it was a one-off search result) → play that precise
                // track + offset.
                await playTrack(t, seekTo: savedPosition > 1 ? savedPosition : nil,
                                autoPlay: autoPlay)
            } else if savedPosition > currentPosition + 2 {
                // SAME track, but the durable session offset is ahead of the DB
                // resume (the DB write was lost when iOS killed the app in the
                // background) → seek to the real last spot, not an older one.
                await playTrack(t, seekTo: savedPosition,
                                recordHistory: false, autoPlay: autoPlay)
            }
        }
    }
}
