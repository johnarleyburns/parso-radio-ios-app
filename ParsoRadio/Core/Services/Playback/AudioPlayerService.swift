import Foundation
import AVFoundation

@MainActor
final class AudioPlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrack: Track?

    var onTrackFinished: (() -> Void)?

    private var player: AVPlayer?
    private var endObserver: (any NSObjectProtocol)?

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.playback.error("AVAudioSession setup failed: \(error)")
        }
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

        player?.play()
        currentTrack = track
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    func skip() {
        tearDownPlayer()
        currentTrack = nil
        isPlaying = false
    }

    private func tearDownPlayer() {
        player?.pause()
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player = nil
    }
}
