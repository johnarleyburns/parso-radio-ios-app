import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false

    func togglePlayPause() {
        isPlaying.toggle()
    }

    func skip() {}
}
