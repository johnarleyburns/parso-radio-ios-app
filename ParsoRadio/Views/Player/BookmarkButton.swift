import SwiftUI

struct BookmarkButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        Button {
            Task { await playerVM.addBookmarkAtCurrentPosition() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "bookmark").font(.title3)
                Text("Bookmark").font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bookmark")
    }
}
