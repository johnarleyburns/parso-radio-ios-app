import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrack: Track?

    var onTrackFinished: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    // Fired every 1 s while playing. PlayerViewModel uses this to persist position
    // for spoken-word channels and to update the UI progress display.
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

    func play(url: URL, track: Track, looping: Bool = false) {
        tearDownPlayer()

        let item = AVPlayerItem(url: url)

        if looping {
            // AVPlayerLooper on AVQueuePlayer gives truly gapless infinite looping
            // at the AVFoundation level — no callback round-trip, no audible gap.
            let queuePlayer = AVQueuePlayer()
            player = queuePlayer
            playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        } else {
            player = AVPlayer(playerItem: item)
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isPlaying = false
                    self?.onTrackFinished?()
                }
            }
        }

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            guard time.isNumeric else { return }
            self?.onTimeUpdate?(time.seconds)
            self?.updateNowPlayingElapsed(time.seconds)
        }

        player?.play()
        currentTrack = track
        isPlaying = true
        updateNowPlayingInfo(for: track)
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
                // then resume playback where we left off. Guard against player being nil
                // if a channel switch happened during the interruption.
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
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
            self?.onTrackFinished?()
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPreviousTrack?()
            return .success
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
        player = nil
    }
}
