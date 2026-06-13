import SwiftUI

struct TransportControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        HStack(spacing: 56) {
            Button { playerVM.skip() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.primary)
            }
            .disabled(playerVM.isLoading)

            Button { playerVM.togglePlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: playerVM.isPlaying ? 0 : 2)
                }
            }
            .disabled(playerVM.isLoading)
        }
        .padding(.vertical, 8)
    }
}
