import SwiftUI

struct FavoriteButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var favorites: FavoritesStore
    var showLabel: Bool = true

    private var isFav: Bool {
        guard let t = playerVM.currentTrack else { return false }
        let fid = t.favoriteID(for: FavoriteKind(mediaKind: playerVM.activeMediaKind))
        return favorites.favorites.contains { $0.id == fid }
    }

    var body: some View {
        Button {
            guard let t = playerVM.currentTrack else { return }
            Task {
                await favorites.toggle(track: t, channel: playerVM.currentChannel,
                                       mediaKind: playerVM.activeMediaKind,
                                       positionSeconds: playerVM.currentPosition)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isFav ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(isFav ? .red : .primary)
                if showLabel { Text(isFav ? "Favorited" : "Favorite").font(.caption2) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFav ? "Remove from favorites" : "Add to favorites")
    }
}
