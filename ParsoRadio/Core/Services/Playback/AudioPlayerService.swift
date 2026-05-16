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
        guard !isLooping, let t = player?.currentTime(), t.isNumeric else { return 0 }
        return t.seconds
    }

    var duration: Double? {
        guard !isLooping,
              let d = player?.currentItem?.duration, d.isNumeric, d.seconds > 0 else { return nil }
        return d.seconds
    }

    private var player: AVPlayer?
    private var playerLooper: AVPlayerLooper?
    private var endObserver: (any NSObjectProtocol)?
    private var timeObserver: Any?
    private var interruptionObserver: (any NSObjectProtocol)?
    private var routeChangeObserver: (any NSObjectProtocol)?

    // Seamless ambient-loop backend. AVPlayerLooper loops the *padded* MP3
    // stream, so Freesound-preview ambiences leave an audible gap at every
    // seam. Instead we decode the clip to PCM once, build an equal-power
    // crossfaded loop buffer, and let an AVAudioPlayerNode loop that buffer —
    // no item boundary, no MP3 priming gap, and the crossfade hides the fact
    // that field recordings aren't authored to loop.
    private let loopEngine = AVAudioEngine()
    private let loopNode = AVAudioPlayerNode()
    private var isLooping = false
    private var loopBuffer: AVAudioPCMBuffer?
    private var loopLoadTask: Task<Void, Never>?

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.playback.error("AVAudioSession setup failed: \(error)")
        }
        loopEngine.attach(loopNode)
        setupRemoteCommandCenter()
        setupAudioSessionObservers()
    }

    func play(url: URL, track: Track, looping: Bool = false) {
        tearDownPlayer()

        if looping {
            startSeamlessLoop(url: url, track: track)
            return
        }

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
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

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4), // 0.25 s — smooth progress bar
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

    // MARK: - Seamless ambient loop (AVAudioEngine + crossfaded PCM buffer)

    private func startSeamlessLoop(url: URL, track: Track) {
        isLooping = true
        currentTrack = track
        isPlaying = true
        updateNowPlayingInfo(for: track)

        loopLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (tmpURL, _) = try await URLSession.app.download(from: url)
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ambientloop").appendingPathExtension("mp3")
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(at: tmpURL, to: dst)

                let file = try AVAudioFile(forReading: dst)
                let format = file.processingFormat            // standard float, deinterleaved
                let frames = AVAudioFrameCount(file.length)
                guard frames > 0,
                      let raw = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
                try file.read(into: raw)
                raw.frameLength = frames
                let loop = Self.makeCrossfadedLoopBuffer(raw) ?? raw

                await MainActor.run {
                    // Bail if the channel was switched while we were downloading.
                    guard self.isLooping else { return }
                    self.loopBuffer = loop
                    self.loopEngine.connect(self.loopNode,
                                            to: self.loopEngine.mainMixerNode,
                                            format: loop.format)
                    do {
                        try self.loopEngine.start()
                        self.loopNode.scheduleBuffer(loop, at: nil,
                                                     options: .loops, completionHandler: nil)
                        if self.isPlaying { self.loopNode.play() }
                    } catch {
                        Log.playback.error("ambient loop engine start failed: \(error)")
                    }
                }
            } catch {
                Log.playback.error("ambient loop load failed: \(error)")
            }
        }
    }

    // Build a loopable buffer: the first `xfade` frames are an equal-power
    // blend of the head (rising) with the clip's tail (falling), and the last
    // `xfade` frames are dropped. The wrap point then connects two ADJACENT
    // source samples (s[loopLen-1] -> s[loopLen]), so there is no click, and
    // the steady ambience masks the energy morph back to the head.
    private static func makeCrossfadedLoopBuffer(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = src.format
        guard let srcData = src.floatChannelData else { return nil }
        let channels = Int(format.channelCount)
        let n = Int(src.frameLength)
        let xfade = min(Int(format.sampleRate * 2.0), n / 3)
        guard xfade > 64 else { return src }   // too short to crossfade — loop raw
        let loopLen = n - xfade
        guard let out = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(loopLen)),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(loopLen)
        let halfPi = Float.pi / 2
        for ch in 0..<channels {
            let s = srcData[ch]
            let o = outData[ch]
            for i in 0..<loopLen {
                if i < xfade {
                    let t = Float(i) / Float(xfade)
                    o[i] = s[i] * sin(t * halfPi) + s[i + loopLen] * cos(t * halfPi)
                } else {
                    o[i] = s[i]
                }
            }
        }
        return out
    }

    func seek(to seconds: Double) {
        guard !isLooping else { return }   // infinite ambience — nothing to seek
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 1))
        updateNowPlayingElapsed(seconds)
    }

    func pause() {
        if isLooping { loopNode.pause() } else { player?.pause() }
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
    }

    func resume() {
        // Re-activate the audio session in case it was deactivated during an interruption.
        try? AVAudioSession.sharedInstance().setActive(true)
        if isLooping {
            try? loopEngine.start()
            loopNode.play()
        } else {
            player?.play()
        }
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
            // AVPlayer auto-pauses; AVAudioEngine does NOT — pause it explicitly.
            if isLooping { loopNode.pause() }
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
                    if isLooping {
                        try loopEngine.start()
                        loopNode.play()
                        isPlaying = true
                        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
                        return
                    }
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
        loopLoadTask?.cancel()
        loopLoadTask = nil
        if isLooping {
            loopNode.stop()
            loopEngine.stop()
            loopEngine.disconnectNodeOutput(loopNode)
            loopBuffer = nil
            isLooping = false
        }
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
