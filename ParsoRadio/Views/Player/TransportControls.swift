import SwiftUI

struct TransportControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        HStack(spacing: 28) {
            Button {
                Task { await playerVM.goToPreviousTrack() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30))
            }
            .accessibilityLabel("Previous track")
            .buttonStyle(.plain)

            Button {
                playerVM.seekBy(-10)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.title2)
            }
            .accessibilityLabel("Back 10 seconds")
            .buttonStyle(.plain)

            Button {
                playerVM.togglePlayPause()
            } label: {
                Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
            }
            .accessibilityLabel(playerVM.isPlaying ? "Pause" : "Play")
            .buttonStyle(.plain)

            Button {
                playerVM.seekBy(10)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.title2)
            }
            .accessibilityLabel("Forward 10 seconds")
            .buttonStyle(.plain)

            Button {
                playerVM.skip()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
            }
            .accessibilityLabel("Next track")
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}
