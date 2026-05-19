import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayerService: ObservableObject {
    enum RepeatMode: String { case off, one }
    var repeatMode: RepeatMode = .off

    @Published var isPlaying = false
    @Published var currentTrack: Track?

    var onTrackFinished: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    // Fired every 0.25 s while playing. PlayerViewModel uses this to update the UI
    // progress display (smooth motion). DB position saves are throttled separately.
    var onTimeUpdate: ((Double) -> Void)?

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
    // Resume offset waiting to be applied once the item is .readyToPlay.
    private var pendingStartSeek: Double = 0

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
    func play(url: URL, track: Track, looping: Bool = false, startAt: Double = 0) {
        tearDownPlayer()

        let item = AVPlayerItem(url: url)
        pendingStartSeek = (looping || startAt <= 0) ? 0 : startAt

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
            // 0:00 and jumps). Per the user spec we deliberately do NOT skip
            // on .failed here — only a true 10 s resolve-timeout (in
            // PlayerViewModel.playTrack) auto-skips a track.
            statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                guard item.status == .readyToPlay else { return }
                Task { @MainActor [weak self] in self?.applyPendingStartSeekAndPlay() }
            }
        }

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4), // 0.25 s — smooth progress bar
            queue: .main
        ) { [weak self] time in
            guard time.isNumeric else { return }
            // Delivered on .main (queue above), so this is genuinely main-actor
            // isolated — assumeIsolated tells the compiler that without an
            // extra Task hop, keeping progress updates frame-tight.
            MainActor.assumeIsolated {
                self?.onTimeUpdate?(time.seconds)
                self?.updateNowPlayingElapsed(time.seconds)
            }
        }

        // No resume offset → start immediately. With a resume offset we wait
        // for .readyToPlay (the status observer seeks then plays) so the seek
        // is never dropped and the user never hears the track restart at 0:00.
        if pendingStartSeek <= 0 {
            player?.play()
        }
        currentTrack = track
        isPlaying = true
        updateNowPlayingInfo(for: track)
    }

    // Called from the .readyToPlay status observer. Applies the deferred
    // resume seek exactly once, then starts playback at that offset.
    private func applyPendingStartSeekAndPlay() {
        guard pendingStartSeek > 0 else { return }
        let target = pendingStartSeek
        pendingStartSeek = 0
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player?.seek(to: time,
                     toleranceBefore: .zero,
                     toleranceAfter: CMTime(seconds: 1, preferredTimescale: 1)) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player?.play()
                self.isPlaying = true
                self.updateNowPlayingElapsed(target)
            }
        }
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
        player?.play()
        isPlaying = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
    }

    func skip() {
        tearDownPlayer()
        currentTrack = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
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

        // When the previous output device becomes unavailable (headphones unplugged,
        // Bluetooth lost), iOS pauses audio automatically. Mirror that in our state.
        if reason == .oldDeviceUnavailable {
            isPlaying = false
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo(for track: Track) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:           track.title,
            MPMediaItemPropertyArtist:          track.artist,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyMediaType:  MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let dur = duration {
            info[MPMediaItemPropertyPlaybackDuration] = dur
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.skip()
            self?.onTrackFinished?()  // Skip always advances regardless of repeat mode
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPreviousTrack?()
            return .success
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
        pendingStartSeek = 0
        player = nil
    }
}
