import SwiftUI

struct AlbumTracksButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var showLabel: Bool = true

    @State private var showAlbum = false

    var body: some View {
        Button {
            guard playerVM.currentTrackIsMultiPart else { return }
            showAlbum = true
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
        .sheet(isPresented: $showAlbum) {
            if let t = playerVM.currentTrack {
                let identifier = t.parentIdentifier ?? t.id
                NavigationStack {
                    ItemDetailView(
                        identifier: identifier,
                        title: t.collectionTitle ?? t.title,
                        creator: t.artist,
                        kind: .album
                    )
                    .environmentObject(playerVM)
                }
            }
        }
    }
}
