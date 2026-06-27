import SwiftUI

struct AlbumTracksButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var showLabel: Bool = true

    var body: some View {
        Button {
            guard playerVM.currentTrackIsMultiPart, let t = playerVM.currentTrack else { return }
            playerVM.surfaceListRequest = .album(
                identifier: t.parentIdentifier ?? t.id,
                title: t.collectionTitle ?? t.title,
                creator: t.artist)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "opticaldisc").font(.title3)
                if showLabel { Text("Album").font(.caption2) }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(playerVM.currentTrackIsMultiPart ? .primary : .secondary)
            .opacity(playerVM.currentTrackIsMultiPart ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!playerVM.currentTrackIsMultiPart)
        .accessibilityLabel(playerVM.currentTrackIsMultiPart ? "Album tracks" : "Album tracks unavailable")
    }
}
