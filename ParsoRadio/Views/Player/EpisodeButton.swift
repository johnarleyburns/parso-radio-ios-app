import SwiftUI

struct EpisodeButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var showLabel: Bool = true

    var body: some View {
        Button {
            playerVM.surfaceListRequest = .episodes
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle").font(.title3)
                if showLabel { Text("Episodes").font(.caption2) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Episodes")
    }
}
