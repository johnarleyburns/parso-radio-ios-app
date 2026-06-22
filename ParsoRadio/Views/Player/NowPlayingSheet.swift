import SwiftUI

struct NowPlayingSheet: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showAddToPlaylist = false

    private var channelCategory: String {
        playerVM.currentChannel?.category ?? ""
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            artwork
                                .padding(.top, 16)

                            trackInfo
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 0)

                    controls
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                    if let msg = playerVM.errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.down")
                                .fontWeight(.semibold)
                        }
                        .accessibilityIdentifier("player.dismiss")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        let kind = playerVM.currentChannel?.mediaKind ?? .music
                        HStack(spacing: 16) {
                            if kind == .audiobook || kind == .lecture || kind == .podcast {
                                AirPlayButton().frame(width: 28, height: 28)
                            }
                            overflowMenu
                        }
                    }
                }
                .task { await favorites.loadAll() }
                .sheet(isPresented: $showAddToPlaylist) {
                    if let t = playerVM.currentTrack {
                        AddItemToPlaylistSheet(track: t)
                            .environmentObject(playlistVM)
                            .environmentObject(playerVM)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        let isAmbient = playerVM.currentChannel?.mediaKind == .ambient
        let size: CGFloat = isAmbient ? 300 : 260

        ZStack {
            if let channel = playerVM.currentChannel,
               channel.contentType == .ambientLoop {
                if let videoURL = AmbientStaticService.bundledVideoURL(forChannelId: channel.id) {
                    LoopingVideoView(url: videoURL, isPlaying: playerVM.isPlaying)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                } else {
                    ProceduralVisualizerView(
                        seed: channel.id,
                        isPlaying: playerVM.isPlaying
                    )
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                }
            } else if let img = playerVM.currentArtwork {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            } else if let channel = playerVM.currentChannel,
                      let channelImage = UIImage(named: channel.id) {
                Image(uiImage: channelImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
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
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 80, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
        }
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

                if let collection = track.collectionTitle ?? {
                    guard let parent = track.parentIdentifier else { return nil }
                    let parts = parent.split(separator: "_")
                    return parts.count >= 2
                        ? parts.dropLast().map { $0.capitalized }.joined(separator: " ")
                        : parent.replacingOccurrences(of: "_", with: " ").capitalized
                }() {
                    Text(collection)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

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
        } else if playerVM.isLoading {
            VStack(spacing: 6) {
                if let name = playerVM.currentChannel?.name {
                    Text(name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text(playerVM.loadingMessage ?? "Finding tracks…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        } else {
            Text("No tracks available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        let kind = playerVM.currentChannel?.mediaKind ?? .music
        let tint = ChannelCategoryStyle.color(for: channelCategory)
        Group {
            switch kind {
            case .music:     MusicControls(tint: tint)
            case .audiobook: SpokenControls(tint: tint, isLecture: false)
            case .lecture:   SpokenControls(tint: tint, isLecture: true)
            case .podcast:   PodcastControls(tint: tint)
            case .ambient:   AmbientControls(tint: tint)
            }
        }
    }

    @ViewBuilder
    private var overflowMenu: some View {
        let kind = playerVM.currentChannel?.mediaKind ?? .music
        Menu {
            if let t = playerVM.currentTrack {

                if kind == .music {
                    Button { showAddToPlaylist = true } label: { Label("Add to playlist", systemImage: "plus.circle") }
                }

                if let shareURL = ShareURLBuilder.url(for: t) {
                    ShareLink(item: shareURL) { Label("Share", systemImage: "square.and.arrow.up") }
                }

                if t.source == "internet_archive" {
                    let identifier = t.parentIdentifier ?? t.id
                    let cleanId = identifier.contains("/") ? String(identifier.split(separator: "/").first ?? "") : identifier
                    if let url = URL(string: "https://archive.org/details/\(cleanId)") {
                        Link(destination: url) { Label("View on archive.org", systemImage: "safari") }
                    }
                }

                if kind == .audiobook || kind == .lecture {
                    Divider()
                    Button { Task { await playerVM.skipToPreviousBook() } } label: {
                        Label(kind == .lecture ? "Previous series" : "Previous book", systemImage: "backward.end")
                    }
                    Button { Task { await playerVM.skipToNextBook() } } label: {
                        Label(kind == .lecture ? "Next series" : "Next book", systemImage: "forward.end")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }
}
