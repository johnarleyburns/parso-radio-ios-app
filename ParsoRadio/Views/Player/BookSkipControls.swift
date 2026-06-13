import SwiftUI

struct BookSkipControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        HStack(spacing: 24) {
            Button {
                Task { await playerVM.skipToPreviousBook() }
            } label: {
                Label("Previous Book", systemImage: "backward.end.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }

            Button {
                Task { await playerVM.skipToNextBook() }
            } label: {
                Label("Next Book", systemImage: "forward.end.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
        }
    }
}
