import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayerService: ObservableObject, AudioEngine {
    enum RepeatMode: String { case off, one }
    var repeatMode: RepeatMode = .off

    // Music: lock-screen shows prev / play-pause / next.
    // Spoken: lock-screen shows skip-back-15 / play-pause / skip-forward-15
    // (more useful inside a long chapter than jumping between chapters).
    enum ContentMode { case music, spokenWord }

    @Published var isPlaying = false
    @Published var currentTrack: Track?
    @Published var embeddedChapters: [Chapter] = []
    @Published var currentChapterIndex: Int = 0
    // Persisted across launches (UserDefaults). Clamped to [0.5, 2.0].
    @Published var playbackRate: Float = AudioPlayerService.savedRate()

    var onTrackFinished: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    // Fired every 0.25 s while playing. PlayerViewModel uses this to update the UI
    // progress display (smooth motion). DB position saves are throttled separately.
    var onTimeUpdate: ((Double) -> Void)?

    private(set) var contentMode: ContentMode = .music
    // Lock-screen ±15 s for spoken-word channels.
    static let skipInterval: TimeInterval = 15

    var currentTime: Double {
        guard let t = player?.currentTime(), t.isNumeric else { return 0 }
        return t.seconds
    }

    var duration: Double? {
        guard let d = player?.currentItem?.duration, d.isNumeric, d.seconds > 0 else { return nil }
        return d.seconds
    }

    private var player: AVPlayer?
    private var playerLooper: AVPlayerLooper?
    private var endObserver: (any NSObjectProtocol)?
    private var timeObserver: Any?
    private var interruptionObserver: (any NSObjectProtocol)?
    private var routeChangeObserver: (any NSObjectProtocol)?
    private var statusObserver: NSKeyValueObservation?
    // Strong ref to the caching resource-loader so AVFoundation (which holds the
    // delegate weakly) doesn't drop it mid-playback. This is the ONE streaming
    // path for all remote audio; nil only for local files / ambient loops.
    private var currentCachingDelegate: CachingResourceLoaderDelegate?
    private static let cachingDelegateQueue = DispatchQueue(label: "guru.parso.resourceLoader")
    // Resume offset waiting to be applied once the item is .readyToPlay.
    private var pendingStartSeek: Double = 0
    // Monotonic per-player token: invalidates stray periodic-time ticks from a
    // torn-down player so they aren't reported as the next track's playback.
    private var playToken = 0
    // Whether playback should actually START once the item is ready. Lets a
    // resume load the track + seek + show its duration while staying PAUSED,
    // instead of the old race where load() paused after the fact and the
    // deferred play sometimes won (or the track sat silent with no progress).
    private var pendingAutoPlay: Bool = true
    // Fired when the item reaches .readyToPlay with its duration, so the UI can
    // show the progress bar / elapsed time even when starting paused.
    var onReady: ((Double) -> Void)?

    var onNonAudio: (() -> Void)?

    /// 3 s timer started on .readyToPlay — if no audio tick arrives by then,
    /// the asset is non-audio (PDF/text that AVPlayer loaded but can't play).
    private var nonAudioTimer: Task<Void, Never>?

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.playback.error("AVAudioSession setup failed: \(error)")
        }
        setupRemoteCommandCenter()
        setupAudioSessionObservers()
    }

    // `startAt` is the resume offset. A seek issued before the AVPlayerItem
    // reaches .readyToPlay is silently dropped by AVPlayer (the duration /
    // seekable ranges aren't known yet), so for a resume we DEFER both the
    // seek and play() until .readyToPlay. This is the fix for "long audiobook
    // resumes from 0:00, especially right after an app upgrade" — a fresh
    // process makes the remote item slower to become ready, so the old
    // seek-immediately-after-play race was lost almost every time.
    func play(url: URL, track: Track, looping: Bool = false, startAt: Double = 0,
              autoPlay: Bool = true) {
        tearDownPlayer()

        // Enforce the streaming cache budget before starting a new track.
        // The streaming cache otherwise grows unbounded during playback.
        let maxMB = UserDefaults.standard.integer(forKey: "maxCacheMB")
        let budget: Int64 = maxMB > 0 ? Int64(maxMB) * 1_048_576 : 250 * 1_048_576
        CacheManager.shared.evictIfNeeded(maxBytes: budget)

        // Build the player item. ALL remote http(s) playback now routes through
        // CachingResourceLoaderDelegate — the single streaming path — so the
        // streamed bytes warm an on-disk prefix cache (replays/seeks serve from
        // disk, and a fully-streamed track becomes an offline copy). Only
        // non-streamed sources take the plain item: ambient LOOPS (bundled, need
        // AVPlayerLooper) and LOCAL files (file://, where cachingURL(for:)
        // returns nil so we fall through here).
        let item: AVPlayerItem
        if !looping,
           let cachingURL = CachingResourceLoaderDelegate.cachingURL(for: url),
           let cache = ContiguousFileCache(fileURL: streamingCachePath(for: track.id)) {
            let asset = AVURLAsset(url: cachingURL)
            let delegate = CachingResourceLoaderDelegate(originalURL: url, cache: cache)
            asset.resourceLoader.setDelegate(delegate, queue: Self.cachingDelegateQueue)
            currentCachingDelegate = delegate
            item = AVPlayerItem(asset: asset)
        } else {
            currentCachingDelegate = nil
            item = AVPlayerItem(url: url)
        }
        pendingStartSeek = (looping || startAt <= 0) ? 0 : startAt
        pendingAutoPlay = autoPlay

        if looping {
            // AVPlayerLooper on AVQueuePlayer: stable, proven, gapless-enough
            // infinite looping at the AVFoundation level. (An AVAudioEngine
            // crossfade was tried for a truly seamless loop but crashed on
            // device and can't be validated without one — reverted.)
            let queuePlayer = AVQueuePlayer()
            player = queuePlayer
            playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        } else {
            // Poor-connectivity policy: do NOT skip a slow track. Buffer well
            // ahead so brief signal drops don't audibly stall, and let AVPlayer
            // wait/rebuffer indefinitely rather than playing into an empty
            // buffer or failing. A genuinely unplayable asset still surfaces via
            // the .failed status observer below; mere slowness just waits.
            item.preferredForwardBufferDuration = 120
            let p = AVPlayer(playerItem: item)
            p.automaticallyWaitsToMinimizeStalling = true
            player = p
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isPlaying = false
                    self?.handleTrackFinished()
                }
            }
            // .readyToPlay → safe to apply the deferred resume seek, THEN
            // start playback (so a long audiobook never audibly starts at
            // 0:00 and jumps).
            statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                switch item.status {
                case .readyToPlay:
                    Task { @MainActor [weak self] in self?.handleItemReady() }
                case .failed:
                    if let err = item.error as? NSError,
                       err.domain == AVFoundationErrorDomain
                        || err.domain == NSOSStatusErrorDomain {
                        Task { @MainActor [weak self] in self?.onNonAudio?() }
                    }
                default:
                    break
                }
            }
        }

        // Tag this player's ticks with a token. A periodic-time block already
        // dispatched before teardown can still run AFTER the next track started
        // — without this guard that stray tick would be reported as the NEW
        // track's playback (falsely "confirming" a track that's actually still
        // buffering, which disarmed the stall watchdog → infinite buffering on
        // skip). Only the live player's ticks are forwarded.
        playToken &+= 1
        let token = playToken
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4), // 0.25 s — smooth progress bar
            queue: .main
        ) { [weak self] time in
            guard time.isNumeric else { return }
            // Delivered on .main (queue above), so this is genuinely main-actor
            // isolated — assumeIsolated tells the compiler that without an
            // extra Task hop, keeping progress updates frame-tight.
            MainActor.assumeIsolated {
                guard let self, self.playToken == token else { return }
                // First real time tick → cancel the non-audio suspicion timer
                self.nonAudioTimer?.cancel()
                self.nonAudioTimer = nil
                self.onTimeUpdate?(time.seconds)
                self.updateNowPlayingElapsed(time.seconds)
                self.updateCurrentChapter(at: time.seconds)
            }
        }

        // Start immediately ONLY when there's no resume seek to apply and we
        // mean to play. With a resume offset we wait for .readyToPlay (handled
        // in handleItemReady) so the seek is never dropped and the user never
        // hears the track restart at 0:00. Looping (ambient) always starts.
        if autoPlay, looping || pendingStartSeek <= 0 {
            player?.play()
            applyRate()
        }
        currentTrack = track
        isPlaying = autoPlay
        updateNowPlayingInfo(for: track)

        // Parse embedded chapters once the item is ready
        Task { [weak self] in
            guard let self else { return }
            let chs = ChapterParser.parse(from: self.player?.currentItem)
            self.embeddedChapters = chs
            self.currentChapterIndex = 0
        }
    }

    // Called once the item is .readyToPlay. Applies any deferred resume seek,
    // reports the now-known duration, and starts playback if autoPlay was
    // requested. Non-audio detection: immediate skip if duration < 0.5s (the
    // 10-second deadline from play() handles the slower cases).
    private func handleItemReady() {
        if let d = player?.currentItem?.duration,
           d.isNumeric, d.seconds < 0.5 {
            onNonAudio?()
            return
        }
        // Post-ready deadline: if no audio within 10 s of .readyToPlay,
        // it's non-audio. Cancelled on first time tick. Safe for normal
        // playback: .readyToPlay means buffers are loaded, so 10 s is
        // plenty even on slow connections (20 s stall watchdog is the
        // ultimate safety net).
        nonAudioTimer?.cancel()
        nonAudioTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      (self.player?.currentTime().seconds ?? 0) < 0.1 else { return }
                self.onNonAudio?()
            }
        }
        if let d = duration { onReady?(d) }
        let target = pendingStartSeek
        pendingStartSeek = 0

        func startIfNeeded(_ at: Double) {
            updateNowPlayingElapsed(at)
            guard pendingAutoPlay else { return }
            player?.play()
            applyRate()
            isPlaying = true
        }

        if target > 0 {
            let time = CMTime(seconds: target, preferredTimescale: 600)
            player?.seek(to: time,
                         toleranceBefore: .zero,
                         toleranceAfter: CMTime(seconds: 1, preferredTimescale: 1)) { _ in
                Task { @MainActor in startIfNeeded(target) }
            }
        } else {
            startIfNeeded(currentTime)
        }
    }

    // AVPlayer resets .rate to 1.0 every play()/resume(), so we reapply the
    // user's persisted rate after each transition. Setting rate on a paused
    // player would start playback, so applyRate() is only called from
    // play()/resume() paths.
    private func applyRate() {
        player?.rate = Self.clampRate(playbackRate)
    }

    /// Variable playback speed (0.5×–2×) — persisted, applied to current and
    /// future items. Setting while paused only updates the stored value;
    /// applyRate() takes effect on the next play()/resume().
    func setPlaybackRate(_ rate: Float) {
        let clamped = Self.clampRate(rate)
        playbackRate = clamped
        UserDefaults.standard.set(Double(clamped), forKey: "playbackRate")
        if isPlaying { applyRate() }
    }

    static func clampRate(_ r: Float) -> Float { min(max(r, 0.5), 2.0) }

    private static func savedRate() -> Float {
        let stored = UserDefaults.standard.double(forKey: "playbackRate")
        guard stored > 0 else { return 1.0 }
        return clampRate(Float(stored))
    }

    /// Toggle which lock-screen / remote commands are active. Music mode shows
    /// prev / play-pause / next; spoken mode shows skip-back-15 / play-pause /
    /// skip-forward-15. Called by PlayerViewModel when a channel loads.
    func setContentMode(_ mode: ContentMode) {
        guard contentMode != mode else { return }
        contentMode = mode
        configureRemoteCommandsForContentMode()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 1))
        updateNowPlayingElapsed(seconds)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
    }

    func resume() {
        // Re-activate the audio session in case it was deactivated during an interruption.
        try? AVAudioSession.sharedInstance().setActive(true)
        // The user explicitly wants playback now: if the item is still waiting on
        // a deferred resume-seek (loaded paused), make sure it PLAYS once ready
        // instead of staying silent.
        pendingAutoPlay = true
        player?.play()
        applyRate()
        isPlaying = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] =
            NSNumber(value: Self.clampRate(playbackRate))
    }

    /// Time-skip within the current track (used by the lock-screen
    /// skipBackward/Forward commands in spoken-word mode). Clamps to
    /// [0, duration].
    func skipTime(by delta: TimeInterval) {
        guard let player else { return }
        let now = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        let target = max(0, now + delta)
        let clamped: Double
        if let dur = duration { clamped = min(target, dur) } else { clamped = target }
        seek(to: clamped)
    }

    func skip() {
        tearDownPlayer()
        currentTrack = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Re-read the REAL player state. The system or another app can pause us
    /// while backgrounded (and AVPlayer doesn't always notify), which left the
    /// UI showing a "pause" icon on a track that was actually paused. Call on
    /// app foreground to resync.
    func syncPlaybackState() {
        guard let player else {
            if isPlaying { isPlaying = false }
            return
        }
        let playing = player.timeControlStatus == .playing
            || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if isPlaying != playing { isPlaying = playing }
    }

    // MARK: - Audio session observers

    private func setupAudioSessionObservers() {
        // Interruption handling: phone calls, Siri, other apps taking audio focus.
        // AVPlayer does NOT auto-resume after an interruption — we must do it explicitly.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleInterruption(notification)
            }
        }

        // Route change: headphones unplugged, Bluetooth device lost, etc.
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            // AVPlayer has already paused itself; sync our state.
            isPlaying = false
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0.0

        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            if options.contains(.shouldResume) {
                // Re-activate the session (it was deactivated when the interruption began)
                // then resume playback where we left off.
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    // Guard against player being nil if a channel switch
                    // happened during the interruption.
                    guard let player else {
                        isPlaying = false
                        return
                    }
                    player.play()
                    isPlaying = true
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: Self.clampRate(playbackRate))
                } catch {
                    Log.playback.error("AVAudioSession reactivation failed after interruption: \(error)")
                }
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        // The previous output device became unavailable (headphones unplugged,
        // Bluetooth/AirPods lost). iOS pauses automatically; mirror that.
        if reason == .oldDeviceUnavailable {
            pauseForRouteFallback()
            return
        }

        // Defensive catch-all: AirPods can briefly drop and the audio route
        // silently FALLS BACK to the built-in speaker while the system still
        // shows them "connected" — the user then hears the phone speaker. If a
        // route change leaves us on the built-in speaker while we were playing
        // through something else, pause instead of blasting the speaker.
        if isPlaying, currentOutputIsBuiltInSpeaker(),
           previousRouteHadExternalOutput(info) {
            pauseForRouteFallback()
        }
    }

    private func pauseForRouteFallback() {
        player?.pause()
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
    }

    private func currentOutputIsBuiltInSpeaker() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .contains { $0.portType == .builtInSpeaker }
    }

    private func previousRouteHadExternalOutput(_ info: [AnyHashable: Any]) -> Bool {
        guard let prev = info[AVAudioSessionRouteChangePreviousRouteKey]
                as? AVAudioSessionRouteDescription else { return false }
        // Headphones, Bluetooth A2DP, AirPlay, USB, car — anything but the
        // phone's own speaker counts as "was playing somewhere external".
        return prev.outputs.contains { $0.portType != .builtInSpeaker }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo(for track: Track, channelName: String? = nil, artwork: UIImage? = nil) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:           track.title,
            MPMediaItemPropertyArtist:          track.artist,
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: Self.clampRate(playbackRate)),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyMediaType:  MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let name = channelName {
            info[MPMediaItemPropertyAlbumTitle] = name
        }
        if let dur = duration {
            info[MPMediaItemPropertyPlaybackDuration] = dur
            if #available(iOS 16.0, *) {
                info[MPNowPlayingInfoPropertyPlaybackProgress] = 0.0
            }
        }
        if let art = artwork {
            let mpArt = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
            info[MPMediaItemPropertyArtwork] = mpArt
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updateNowPlayingArtwork(_ artwork: UIImage) {
        let mpArt = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = mpArt
    }

    func updateNowPlayingChannel(_ channelName: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] = channelName
    }

    private func updateCurrentChapter(at seconds: Double) {
        guard !embeddedChapters.isEmpty else { return }
        var idx = 0
        for (i, ch) in embeddedChapters.enumerated() {
            if seconds >= ch.startTime { idx = i }
        }
        if idx != currentChapterIndex {
            currentChapterIndex = idx
            let ch = embeddedChapters[idx]
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] = ch.title
        }
    }

    func seekToChapter(_ chapter: Chapter) {
        seek(to: chapter.startTime)
    }

    private func updateNowPlayingElapsed(_ seconds: Double) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        if let dur = duration {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = dur
        }
    }

    // MARK: - Remote Command Center (lock screen / headphone controls)

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying { self.pause() } else { self.resume() }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.skip()
            self?.onTrackFinished?()  // Skip always advances regardless of repeat mode
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPreviousTrack?()
            return .success
        }

        // Lock-screen ±15 s buttons for spoken-word channels (audiobooks /
        // lectures / news). iOS shows these in place of prev/next when they
        // are enabled, so we toggle which set is active via setContentMode.
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipTime(by: -Self.skipInterval)
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipTime(by: Self.skipInterval)
            return .success
        }

        // Initial state matches the default contentMode (music).
        configureRemoteCommandsForContentMode()
    }

    private func configureRemoteCommandsForContentMode() {
        let center = MPRemoteCommandCenter.shared()
        switch contentMode {
        case .music:
            center.nextTrackCommand.isEnabled = true
            center.previousTrackCommand.isEnabled = true
            center.skipBackwardCommand.isEnabled = false
            center.skipForwardCommand.isEnabled = false
        case .spokenWord:
            center.nextTrackCommand.isEnabled = false
            center.previousTrackCommand.isEnabled = false
            center.skipBackwardCommand.isEnabled = true
            center.skipForwardCommand.isEnabled = true
        }
    }

    // MARK: - Repeat mode

    private func handleTrackFinished() {
        switch repeatMode {
        case .one:
            seek(to: 0)
            resume()
        case .off:
            onTrackFinished?()
        }
    }

    // MARK: - Teardown

    private func tearDownPlayer() {
        // Invalidate any in-flight periodic-time ticks from the outgoing player.
        playToken &+= 1
        nonAudioTimer?.cancel()
        nonAudioTimer = nil
        player?.pause()
        playerLooper?.disableLooping()
        playerLooper = nil
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        // Force-cancel the previous resource loader's URLSession BEFORE letting
        // the asset chain release. Otherwise on a fast track-skip the old
        // session can keep an in-flight Range fetch alive racing the new
        // track's loader (suspected cause of "track 2 buffers forever").
        currentCachingDelegate?.shutdown()
        currentCachingDelegate = nil
        pendingStartSeek = 0
        player = nil
    }

    /// Delete the streaming cache file for a track so a re-visit starts fresh.
    /// Call when a track has failed to stream — avoids "spins forever on
    /// re-visit" from a partially-written or corrupted cache file.
    func invalidateStreamingCache(for trackID: String) {
        let url = streamingCachePath(for: trackID)
        try? FileManager.default.removeItem(at: url)
    }

    /// Filesystem path for the experimental streaming-cache file for one track.
    /// Lives under cachesDirectory so iOS can evict; ":" / "/" in ids are
    /// sanitised so per-file IA ids (e.g. "identifier/file.mp3") map to a flat path.
    private func streamingCachePath(for trackID: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("StreamingCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = trackID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return dir.appendingPathComponent(safe).appendingPathExtension("audio")
    }
}
