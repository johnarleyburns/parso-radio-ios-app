import SwiftUI

struct TransportControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                Button {
                    playerVM.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18))
                        .foregroundStyle(playerVM.shuffleMode ? .blue : .secondary)
                }
                .accessibilityLabel(playerVM.shuffleMode ? "Shuffle on" : "Shuffle off")
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)

                Spacer()

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

                Spacer()

                Button {
                    playerVM.toggleRepeat()
                } label: {
                    Image(systemName: "repeat.1")
                        .font(.system(size: 18))
                        .foregroundStyle(playerVM.repeatMode == .one ? .blue : .secondary)
                }
                .accessibilityLabel(playerVM.repeatMode == .one ? "Repeat on" : "Repeat off")
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
    }
}
