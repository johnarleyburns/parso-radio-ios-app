import Foundation
import SwiftUI
import UIKit
import MediaPlayer

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
    // A track has 10 s to start; on failure/timeout we auto-skip to the next.
    // Capped so a channel where everything fails doesn't loop forever.
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
                // Ambient loop channels: seek back to the beginning instead of advancing.
                if let channel = self.currentChannel, channel.contentType == .ambientLoop {
                    self.audioPlayer.seek(to: 0)
                    self.audioPlayer.resume()
                    self.isPlaying = true
                    self.currentPosition = 0
                    return
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
                }
            }
        }
    }

    func load(channel: Channel, autoPlay: Bool = true) async {
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
        isLoading = true
        loadingMessage = "Finding tracks…"
        errorMessage = nil
        currentPosition = 0
        trackDuration = nil

        do {
            let fetched: [Track]

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

        // Resume the last-played track for all channel types.
        // Spoken-word resumes at exact position; music restarts the same track from the beginning.
        if let saved = await db.loadPosition(channelId: channel.id),
           let track = await db.fetchTrack(id: saved.trackId) {
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
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "advance-track") {
            UIApplication.shared.endBackgroundTask(bgTask)
        }
        defer { UIApplication.shared.endBackgroundTask(bgTask) }

        // Librivox sequential multi-part: advance to next part before random pick
        if let current = currentTrack, current.parentIdentifier != nil {
            if let nextPart = await queueManager.nextPart(after: current, channel: channel) {
                await playTrack(nextPart, seekTo: nil)
                return
            }
        }

        guard let track = await queueManager.nextTrack(channel: channel, shuffleMode: shuffleMode) else {
            currentTrack = nil
            isPlaying = false
            if errorMessage == nil {
                errorMessage = "No tracks found. Try refreshing or select another channel."
            }
            isLoading = false
            return
        }
        await playTrack(track, seekTo: nil)
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
        currentTrack = track
        // Pre-set duration from track metadata so scrubber renders before AVPlayer buffers.
        trackDuration = track.duration > 0 ? track.duration : nil
        // Load artwork asynchronously so playback starts without waiting
        Task { [weak self] in
            guard let self else { return }
            let art = await ArtworkService.shared.artwork(for: track)
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
            } else {
                url = track.streamURL
            }
            audioPlayer.play(url: url, track: track, looping: currentChannel?.contentType == .ambientLoop)
            if let seconds = seekTo, seconds > 0 {
                audioPlayer.seek(to: seconds)
                currentPosition = seconds
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
            }
            scheduleStallWatchdog(for: track, seekTo: seekTo)
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

        // 2. DB-first: already-expanded parts win, no network needed.
        let dbParts = await db.fetchTracks(forParentIdentifier: identifier)
        if dbParts.count >= 2 {
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
            let stampTags = (currentChannel?.iaQueryEntry?.matchTags ?? [])
                .map { Channel.stampToken($0) }
            let stamped = fetched.map { $0.stamped(with: stampTags) }
            await db.saveTracks(stamped)
            await db.setIsMultiPart(true, forTrackId: identifier)
            let ordered = stamped.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
            itemPartsCache[identifier] = ordered
            return ordered
        } catch {
            // Network error: do NOT cache (absence = retry on next load).
            return nil
        }
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

    // A track that resolved but never actually starts (AVPlayer stalls on a
    // dead/slow URL) must not silently hang the channel. After loadTimeout,
    // if we're still on this track and no audio has progressed, auto-skip.
    private func scheduleStallWatchdog(for track: Track, seekTo: Double?) {
        if currentChannel?.contentType == .ambientLoop { return }  // engine loop: no position updates
        let resumed = (seekTo ?? 0) > 0
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.loadTimeout ?? 10) * 1_000_000_000))
            guard let self else { return }
            guard self.currentTrack?.id == track.id,
                  self.isPlaying,
                  !resumed,
                  self.currentPosition < 0.5 else { return }
            await self.handleLoadFailure(track)
        }
    }

    // Failure/timeout/stall: auto-advance to the next track instead of
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

    func loadPlaylist(_ playlist: Playlist, startingAt track: Track? = nil) async {
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
        await playTrack(startTrack, seekTo: 0, recordHistory: false)
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
}
