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

    // Sleep timer: non-nil endsAt → a Task is counting down to pause(); the
    // "End of Track" flag stops at the next natural onTrackFinished.
    @Published var sleepTimerEndsAt: Date? = nil
    @Published var sleepAtEndOfTrack: Bool = false
    private var sleepTimerTask: Task<Void, Never>? = nil

    // Bookmarks for the currently-playing track. Reloaded on track change.
    @Published var bookmarksForCurrentTrack: [Bookmark] = []
    // Mirrors audioPlayer.playbackRate (Float) as a Double for SwiftUI bindings.
    @Published var playbackRate: Double

    let audioPlayer: AudioPlayerService

    private let db: DatabaseService
    private let archiveService: InternetArchiveService
    private let fmaService: FMAService
    private let oxfordService: OxfordLecturesService
    private let podcastService: PodcastRSSService
    private let ambientService: AmbientStaticService
    private let queueManager: QueueManager
    private let downloadManager: DownloadManager
    var currentChannel: Channel?

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
    private let loadTimeout: Double = 10
    private let maxConsecutiveLoadFailures = 8
    private var consecutiveLoadFailures = 0

    init(
        db: DatabaseService,
        archiveService: InternetArchiveService,
        fmaService: FMAService,
        queueManager: QueueManager,
        audioPlayer: AudioPlayerService,
        downloadManager: DownloadManager,
        oxfordService: OxfordLecturesService = OxfordLecturesService(),
        podcastService: PodcastRSSService = PodcastRSSService(),
        ambientService: AmbientStaticService = AmbientStaticService()
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
        self.playbackRate = Double(audioPlayer.playbackRate)

        // Evict stale tracks on launch if DB is large (>5 000 rows, older than 30 days).
        Task { [weak self] in
            guard let self else { return }
            let count = await self.db.trackCount()
            if count > 5000 { await self.db.evictOldTracks() }
        }

        // Issue 3: save isPlaying so cold-start can decide whether to auto-play.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                UserDefaults.standard.set(self.isPlaying, forKey: "wasPlayingOnQuit")
                // Safety-net: never lose the user's spot — autosave on resign.
                self.saveAutosaveForCurrentTrack()
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

        audioPlayer.onTimeUpdate = { [weak self] seconds in
            Task { @MainActor [weak self] in
                guard let self, !self.isScrubbing else { return }
                self.currentPosition = seconds
                self.trackDuration = self.audioPlayer.duration
                // (minTrackDuration is enforced invisibly in advanceToNext via
                // assetDuration pre-screening, before the track is revealed.)
                // Persist position for spoken-word channels so the user can resume.
                // Throttled: write DB at most once every 5 s (timer fires 4×/s).
                if let channel = self.currentChannel,
                   channel.contentType == .spokenWord,
                   let track = self.currentTrack,
                   seconds - self.lastPositionSaveTime >= 5.0 {
                    self.lastPositionSaveTime = seconds
                    await self.db.savePosition(
                        channelId: channel.id,
                        trackId: track.id,
                        seconds: seconds
                    )
                } else if let playlist = self.currentPlaylist,
                          let track = self.currentTrack,
                          seconds - self.lastPositionSaveTime >= 5.0 {
                    // Resume support: keep the playlist's track + offset
                    // current (critical for long multi-part audiobooks).
                    self.lastPositionSaveTime = seconds
                    await self.db.savePosition(
                        channelId: Self.playlistKey(playlist.id),
                        trackId: track.id,
                        seconds: seconds
                    )
                }
            }
        }

    }

    func load(channel: Channel, autoPlay: Bool = true) async {
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

        currentChannel = channel
        // Lock-screen controls follow the content: spoken-word channels get
        // ±15 s skip buttons; music channels get next/prev track.
        audioPlayer.setContentMode(channel.contentType == .spokenWord ? .spokenWord : .music)
        isLoading = true
        loadingMessage = "Finding tracks…"
        errorMessage = nil
        currentPosition = 0
        trackDuration = nil

        // Hoisted so the post-fetch resume / News-newest logic can see it.
        var fetched: [Track] = []

        do {
            if channel.feedURL != nil {
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
                fetched = try await archiveService.fetchTracks(
                    iaQuery: entry.iaQuery, matchTags: entry.matchTags
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
            downloadManager.prefetchNext(fetched)
            channelDescription = channel.detailDescription
            channelTrackCount = fetched.count
            channelMostRecentDate = fetched.compactMap(\.addedDate).max()
            currentPlaylist = nil
            playlistTracks = []
            playlistIndex = 0
        } catch let urlError as URLError
            where urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
            if currentTrack == nil {
                errorMessage = "No internet connection. Check your network and try again."
            }
        } catch {
            if currentTrack == nil {
                errorMessage = "Could not fetch tracks. Try another channel."
            }
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
                await playTrack(newest, seekTo: nil)
                if !autoPlay && isPlaying { audioPlayer.pause(); isPlaying = false }
                isLoading = false
                loadingMessage = nil
                return
            }
        }

        // Resume the last-played track for all channel types.
        // Spoken-word resumes at exact position; music restarts the same track from the beginning.
        if let saved, let track = await db.fetchTrack(id: saved.trackId) {
            loadingMessage = "Resuming \"\(track.title)\"…"
            let seekTo: Double? = channel.contentType == .spokenWord ? saved.seconds : nil
            await playTrack(track, seekTo: seekTo)
        } else {
            loadingMessage = "Starting playback…"
            await advanceToNext()
        }

        if !autoPlay && isPlaying {
            audioPlayer.pause()
            isPlaying = false
        }

        isLoading = false
        loadingMessage = nil
    }

    func togglePlayPause() {
        if audioPlayer.isPlaying {
            // Capture the spot BEFORE telling the player to pause — once the
            // user is paused the position will not advance, but if they exit
            // the app right after a pause we still want the latest offset.
            saveAutosaveForCurrentTrack()
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

    private func advanceToNext() async {
        // Playlist mode: advance within the playlist's ordered tracks.
        // (currentChannel is nil in playlist mode, so the channel queue path
        // below would otherwise do nothing — which is why <next> was dead.)
        if currentPlaylist != nil {
            await advancePlaylist()
            return
        }
        guard let channel = currentChannel else { return }

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

        // Librivox sequential multi-part: advance to next part before random pick
        if let current = currentTrack, current.parentIdentifier != nil {
            if let nextPart = await queueManager.nextPart(after: current, channel: channel) {
                await playTrack(nextPart, seekTo: nil)
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
        await playTrack(track, seekTo: nil)
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
            guard let resolved = try? await withTimeout(loadTimeout, {
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

    private func playTrack(_ track: Track, seekTo: Double?, recordHistory: Bool = true) async {
        // Hide the book/album buttons immediately; the probe re-enables them
        // once it confirms this track belongs to a multi-file item.
        currentTrackIsMultiPart = false
        // UC3: push current track onto history before replacing it.
        if recordHistory, let existing = currentTrack {
            playHistory.append(existing)
            if playHistory.count > historyLimit { playHistory.removeFirst() }
        }
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
            let art = await ArtworkService.shared.artwork(for: track)
            // Stale-guard: a slow fetch for a track the user already skipped
            // past must NOT overwrite the current track's (cleared) artwork.
            guard self.currentTrack?.id == track.id else { return }
            self.currentArtwork = art
            if let art {
                let uiColor = ArtworkService.shared.dominantColor(from: art)
                self.artworkDominantColor = Color(uiColor)
                let mpArt = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = mpArt
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
                    url = try await withTimeout(loadTimeout) {
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
            let resumeAt = max(effectiveSeek, 0)
            audioPlayer.play(url: url, track: track,
                             looping: currentChannel?.contentType == .ambientLoop,
                             startAt: resumeAt)
            if resumeAt > 0 {
                // Show the resume position in the UI immediately; AudioPlayer
                // applies the actual seek once the item is .readyToPlay.
                currentPosition = resumeAt
            }
            isPlaying = true
            isLoading = false
            loadingMessage = nil
            errorMessage = nil
            consecutiveLoadFailures = 0

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
            probeCurrentTrack()
        } catch {
            await handleLoadFailure(track)
        }
    }

    // MARK: - Whole book/album

    // Silent, async probe run at the end of playTrack. The button only
    // appears after it resolves; it never blocks playback or shows a spinner.
    private func probeCurrentTrack() {
        guard let track = currentTrack, track.source == "internet_archive" else {
            currentTrackIsMultiPart = false
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

    // Runs `op` but throws if it doesn't finish within `seconds`.
    private func withTimeout<T: Sendable>(
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

    // Failure/timeout: auto-advance to the next track instead of
    // dead-ending. Capped so a channel where everything fails stops cleanly.
    private func handleLoadFailure(_ track: Track) async {
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
        await advanceToNext()
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
        isPlaying = false
        currentTrack = pre
        trackDuration = (pre?.duration ?? 0) > 0 ? pre?.duration : nil
        isLoading = true
        loadingMessage = "Loading…"
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
        playHistory = []
        channelDescription = ""
        beginTransition(pre: pre)
        await playTrack(pre, seekTo: nil, recordHistory: false)
        isLoading = false
        loadingMessage = nil
    }

    // Per-playlist position is stored in the same positions table as
    // channels, namespaced so it can never collide with a real channel id
    // (channel ids contain no ':').
    static func playlistKey(_ playlistId: String) -> String { "playlist:\(playlistId)" }

    func loadPlaylist(_ playlist: Playlist,
                       startingAt track: Track? = nil,
                       seekTo: Double = 0) async {
        // Save the outgoing track's spot before switching context.
        saveAutosaveForCurrentTrack()
        beginTransition(pre: track)
        currentPlaylist = playlist
        currentChannel = nil
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
        await playTrack(startTrack, seekTo: seekTo, recordHistory: false)
    }

    // The saved spot in a playlist (track still present + offset), or nil.
    func savedPlaylistResume(_ playlist: Playlist) async -> (track: Track, seconds: Double)? {
        guard let saved = await db.loadPosition(channelId: Self.playlistKey(playlist.id))
        else { return nil }
        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        guard let track = tracks.first(where: { $0.id == saved.trackId }) else { return nil }
        return (track, saved.seconds)
    }

    // Resume a playlist exactly where the user left off (the saved track at
    // its saved offset). Falls back to a normal play-from-top if nothing saved.
    func resumePlaylist(_ playlist: Playlist) async {
        if let resume = await savedPlaylistResume(playlist) {
            await loadPlaylist(playlist, startingAt: resume.track, seekTo: resume.seconds)
        } else {
            await loadPlaylist(playlist)
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
        if let dur = trackDuration, dur > 0, pos > dur - 5 { return }
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
}
