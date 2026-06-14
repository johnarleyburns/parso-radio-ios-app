import SwiftUI

struct ChapterButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var showChapters = false

    var body: some View {
        Button {
            showChapters = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle").font(.title3)
                Text("Chapters").font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapters")
        .sheet(isPresented: $showChapters) {
            ChapterListView()
                .environmentObject(playerVM)
        }
    }
}
