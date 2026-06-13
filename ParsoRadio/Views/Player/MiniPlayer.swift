import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var showNowPlaying = false

    var body: some View {
        if playerVM.currentTrack != nil {
            Button {
                showNowPlaying = true
            } label: {
                HStack(spacing: 12) {
                    if let channel = playerVM.currentChannel {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ChannelCategoryStyle.gradient(for: channel.category))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: channel.icon)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                    }

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
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showNowPlaying) {
                NowPlayingSheet()
                    .environmentObject(playerVM)
            }
        }
    }
}
