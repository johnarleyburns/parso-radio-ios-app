import SwiftUI

struct ChapterButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var showChapters = false

    var body: some View {
        Button {
            showChapters = true
        } label: {
            Label("Chapters", systemImage: "list.bullet.rectangle")
                .font(.caption)
        }
        .sheet(isPresented: $showChapters) {
            ChapterListView()
                .environmentObject(playerVM)
        }
    }
}
