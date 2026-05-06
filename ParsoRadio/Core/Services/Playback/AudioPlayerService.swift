import Foundation
import AVFoundation

@MainActor
final class AudioPlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrack: Track?

    private var player: AVPlayer?

    func play(_ track: Track) {
        let url: URL
        if let path = track.localFilePath,
           FileManager.default.fileExists(atPath: path) {
            url = URL(fileURLWithPath: path)
        } else {
            url = track.streamURL
        }
        player = AVPlayer(url: url)
        player?.play()
        currentTrack = track
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func skip() {
        pause()
        currentTrack = nil
    }
}
