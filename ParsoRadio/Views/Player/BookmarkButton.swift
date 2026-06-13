import SwiftUI

struct BookmarkButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var showSheet = false

    var body: some View {
        Button {
            Task { await playerVM.addBookmarkAtCurrentPosition() }
        } label: {
            Label("Bookmark", systemImage: "bookmark")
                .font(.caption)
        }
    }
}
