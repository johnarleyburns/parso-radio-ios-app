import SwiftUI

struct BookSkipControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    private var isLecture: Bool {
        playerVM.currentChannel?.mediaKind == .lecture
    }

    var body: some View {
        PlayerAccessoryButton(
            systemImage: "backward.end.fill",
            title: isLecture ? "Prev Series" : "Prev Book"
        ) {
            Task { await playerVM.skipToPreviousBook() }
        }
        PlayerAccessoryButton(
            systemImage: "forward.end.fill",
            title: isLecture ? "Next Series" : "Next Book"
        ) {
            Task { await playerVM.skipToNextBook() }
        }
    }
}
