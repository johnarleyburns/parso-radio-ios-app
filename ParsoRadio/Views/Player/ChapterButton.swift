import SwiftUI

struct ChapterButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var showLabel: Bool = true

    private var isLecture: Bool {
        playerVM.currentChannel?.mediaKind == .lecture
    }

    private var label: String { isLecture ? "Lectures" : "Chapters" }

    var body: some View {
        Button {
            playerVM.surfaceListRequest = .chapters
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle").font(.title3)
                if showLabel { Text(label).font(.caption2) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
