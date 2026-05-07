import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class AudioPlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrack: Track?

    var onTrackFinished: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    // Fired every ~5 s while playing. PlayerViewModel uses this to persist position
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
    private var endObserver: (any NSObjectProtocol)?
    private var timeObserver: Any?

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.playback.error("AVAudioSession setup failed: \(error)")
        }
        setupRemoteCommandCenter()
    }

    func play(url: URL, track: Track) {
        tearDownPlayer()

        let item = AVPlayerItem(url: url)
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

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1),
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
