import SwiftUI

struct NowPlayingSheet: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss

    private var behavior: PlaybackBehavior {
        playerVM.currentChannel?.behavior ?? MediaKind.music.behavior
    }

    private var channelCategory: String {
        playerVM.currentChannel?.category ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    artwork
                        .padding(.top, 16)

                    trackInfo

                    TransportControls()
                        .disabled(playerVM.isLoading)

                    if let track = playerVM.currentTrack {
                        globalControls(for: track)
                    }

                    behaviorSpecificControls

                    if let msg = playerVM.errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .fontWeight(.semibold)
                    }
                }
            }
            .task { await favorites.loadAll() }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            if let img = playerVM.currentArtwork {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 260, height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            } else {
                let gradient = playerVM.currentChannel.map {
                    ChannelCategoryStyle.gradient(for: $0.category)
                } ?? LinearGradient(
                    colors: [Color(.systemGray3), Color(.systemGray5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                let icon = playerVM.currentChannel?.icon ?? "music.note"
                RoundedRectangle(cornerRadius: 28)
                    .fill(gradient)
                    .frame(width: 260, height: 260)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                    .overlay {
                        if playerVM.isLoading && playerVM.currentTrack == nil {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(1.5)
                                if let msg = playerVM.loadingMessage {
                                    Text(msg)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: 80, weight: .light))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
            }
        }
        .opacity(playerVM.isLoading && playerVM.currentTrack != nil ? 0.75 : 1)
        .animation(.easeInOut(duration: 0.3), value: playerVM.isLoading)
    }

    @ViewBuilder
    private var trackInfo: some View {
        if let track = playerVM.currentTrack {
            VStack(spacing: 6) {
                Text(track.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let composer = track.composer, composer != track.artist.lowercased() {
                    Text("Composed by \(composer.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if playerVM.isLoading, let msg = playerVM.loadingMessage {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text(msg).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 8) {
                        LicenseDisplay.label(track.license)
                        SourceDisplay.tag(track.source)
                    }
                    .padding(.top, 4)
                }
            }
        } else if !playerVM.isLoading {
            Text("No tracks available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func globalControls(for track: Track) -> some View {
        HStack(spacing: 24) {
            Button {
                Task {
                    await favorites.toggle(track: track, channel: playerVM.currentChannel,
                                           positionSeconds: playerVM.currentPosition)
                }
            } label: {
                let fid = track.favoriteID(for: track.favoriteKind(channel: playerVM.currentChannel))
                let isFav = favorites.favorites.contains(where: { $0.id == fid })
                Image(systemName: isFav ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(isFav ? .red : .secondary)
            }
            .accessibilityLabel(
                (favorites.favorites.contains(where: {
                    $0.id == track.favoriteID(for: track.favoriteKind(channel: playerVM.currentChannel))
                }) ? "Remove from favorites" : "Add to favorites")
            )

            if let shareURL = ShareURLBuilder.url(for: track) {
                ShareLink(item: shareURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                }
                .accessibilityLabel("Share")
            }

            AirPlayButton()
                .frame(width: 32, height: 32)
                .accessibilityLabel("AirPlay")

            if track.source == "internet_archive" {
                let identifier = track.parentIdentifier ?? track.id
                let cleanId = identifier.contains("/")
                    ? String(identifier.split(separator: "/").first ?? "")
                    : identifier
                if let url = URL(string: "https://archive.org/details/\(cleanId)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                            .font(.title3)
                    }
                    .accessibilityLabel("View on archive.org")
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var behaviorSpecificControls: some View {
        let b = behavior
        VStack(spacing: 16) {
            if b.showsScrubbableProgress {
                ScrubBar(tint: ChannelCategoryStyle.color(for: channelCategory))
            }

            if b.allowsShuffleToggle {
                HStack(spacing: 24) {
                    ShuffleControl()
                    RepeatControl()
                }
            }

            HStack(spacing: 20) {
                if b.supportsSpeedControl { SpeedControl() }
                if b.supportsSleepTimer { SleepTimerControl() }
            }

            HStack(spacing: 20) {
                if b.supportsChapters { ChapterButton() }
                if b.supportsBookmarks { BookmarkButton() }
            }

            if b.supportsBookSkip { BookSkipControls() }
        }
    }
}

private struct ShuffleControl: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var body: some View {
        Button {
            playerVM.toggleShuffle()
        } label: {
            Label("Shuffle", systemImage: playerVM.shuffleMode ? "shuffle" : "shuffle")
                .font(.caption)
                .foregroundStyle(playerVM.shuffleMode ? .blue : .secondary)
        }
    }
}

private struct RepeatControl: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var body: some View {
        Button {
            playerVM.toggleRepeat()
        } label: {
            Label("Repeat", systemImage: playerVM.repeatMode == .one ? "repeat.1" : "repeat")
                .font(.caption)
                .foregroundStyle(playerVM.repeatMode == .one ? .blue : .secondary)
        }
    }
}
