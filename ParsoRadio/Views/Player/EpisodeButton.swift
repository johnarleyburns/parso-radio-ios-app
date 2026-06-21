import SwiftUI

struct EpisodeButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var showEpisodes = false
    var showLabel: Bool = true

    var body: some View {
        Button {
            showEpisodes = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle").font(.title3)
                if showLabel { Text("Episodes").font(.caption2) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Episodes")
        .sheet(isPresented: $showEpisodes) {
            NavigationStack {
                EpisodeListView()
                    .environmentObject(playerVM)
            }
        }
    }
}
