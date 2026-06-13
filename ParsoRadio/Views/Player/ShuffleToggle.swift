import SwiftUI

struct ShuffleToggle: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        Button {
            playerVM.toggleShuffle()
        } label: {
            Label("Shuffle", systemImage: playerVM.shuffleMode
                  ? "shuffle" : "shuffle")
                .font(.caption)
                .foregroundStyle(playerVM.shuffleMode ? .blue : .secondary)
        }
    }
}
