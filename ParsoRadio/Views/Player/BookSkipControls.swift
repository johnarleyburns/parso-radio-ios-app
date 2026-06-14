import SwiftUI

struct BookSkipControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        PlayerAccessoryButton(
            systemImage: "backward.end.fill",
            title: "Prev Book"
        ) {
            Task { await playerVM.skipToPreviousBook() }
        }
        PlayerAccessoryButton(
            systemImage: "forward.end.fill",
            title: "Next Book"
        ) {
            Task { await playerVM.skipToNextBook() }
        }
    }
}
