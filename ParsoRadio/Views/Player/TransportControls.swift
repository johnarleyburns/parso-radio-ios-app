import SwiftUI

struct TransportControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Task { await playerVM.goToPreviousTrack() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30))
            }
            .accessibilityLabel("Previous track")
            .buttonStyle(.plain)

            Spacer()

            Button {
                playerVM.togglePlayPause()
            } label: {
                Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
            }
            .accessibilityLabel(playerVM.isPlaying ? "Pause" : "Play")
            .buttonStyle(.plain)

            Spacer()

            Button {
                playerVM.skip()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
            }
            .accessibilityLabel("Next track")
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}
