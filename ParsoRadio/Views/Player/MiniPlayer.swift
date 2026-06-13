import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @EnvironmentObject var favorites: FavoritesStore
    @State private var showPlayer = false

    var body: some View {
        if playerVM.currentTrack != nil {
            Button {
                showPlayer = true
            } label: {
                HStack(spacing: 12) {
                    ArtworkThumbnail(track: playerVM.currentTrack!, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playerVM.currentTrack?.title ?? "")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(playerVM.currentTrack?.artist ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        playerVM.togglePlayPause()
                    } label: {
                        Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .overlay(Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(.separator),
                         alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mini player: \(playerVM.currentTrack?.title ?? "")")
            .accessibilityHint("Opens the full player screen")
            .fullScreenCover(isPresented: $showPlayer) {
                NowPlayingSheet()
                    .environmentObject(playerVM)
                    .environmentObject(favorites)
            }
        }
    }
}
