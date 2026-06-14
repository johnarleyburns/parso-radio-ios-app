import SwiftUI

struct NowPlayingSheet: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showAddToPlaylist = false

    private var behavior: PlaybackBehavior {
        playerVM.currentChannel?.behavior ?? MediaKind.music.behavior
    }

    private var channelCategory: String {
        playerVM.currentChannel?.category ?? ""
    }

    var body: some View {
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

                bottomControls
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
    private var bottomControls: some View {
        let b = behavior
        let tint = ChannelCategoryStyle.color(for: channelCategory)

        VStack(spacing: 8) {
            if let track = playerVM.currentTrack {
                progressSection(track: track, tint: tint)

                TransportControls()
                    .disabled(playerVM.isLoading)

                if b.allowsShuffleToggle {
                    HStack(spacing: 0) {
                        ShuffleControl()

                        Spacer()

                        HStack(spacing: 16) {
                            if track.source == "internet_archive" {
                                archiveLink(for: track)
                            }
                            AirPlayButton()
                                .frame(width: 28, height: 28)
                            Button {
                                showAddToPlaylist = true
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.body)
                            }
                            .accessibilityLabel("Add to playlist")
                            if b.supportsSleepTimer {
                                sleepTimerMenu
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)

                        Spacer()

                        RepeatControl()
                    }
                    .sheet(isPresented: $showAddToPlaylist) {
                        AddItemToPlaylistSheet(track: track)
                            .environmentObject(playlistVM)
                            .environmentObject(playerVM)
                    }
                }

                if !b.allowsShuffleToggle {
                    actionButtons(for: track)
                }
            } else {
                TransportControls()
                    .disabled(playerVM.isLoading)
            }

            HStack(spacing: 20) {
                if b.supportsSpeedControl { SpeedControl() }
                if b.supportsSleepTimer, !b.allowsShuffleToggle { SleepTimerControl() }
            }

            HStack(spacing: 20) {
                if b.supportsChapters { ChapterButton() }
                if b.supportsBookmarks { BookmarkButton() }
            }

            if b.supportsBookSkip { BookSkipControls() }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func progressSection(track: Track, tint: Color) -> some View {
        let fid = track.favoriteID(for: track.favoriteKind(channel: playerVM.currentChannel))
        let isFav = favorites.favorites.contains(where: { $0.id == fid })
        let remaining = (playerVM.trackDuration ?? 0) - playerVM.currentPosition

        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(spacing: 2) {
                    Button {
                        Task {
                            await favorites.toggle(track: track, channel: playerVM.currentChannel,
                                                   positionSeconds: playerVM.currentPosition)
                        }
                    } label: {
                        Image(systemName: isFav ? "heart.fill" : "heart")
                            .font(.body)
                            .foregroundStyle(isFav ? .red : .secondary)
                    }
                    .accessibilityLabel(isFav ? "Remove from favorites" : "Add to favorites")

                    Text(playerVM.currentPosition.formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                VStack(spacing: 2) {
                    if let shareURL = ShareURLBuilder.url(for: track) {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body)
                        }
                        .accessibilityLabel("Share")
                    } else {
                        Color.clear.frame(width: 17, height: 17)
                    }

                    Text("-\(remaining.formattedTime)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)

            ScrubBar(tint: tint)
        }
    }

    @ViewBuilder
    private func actionButtons(for track: Track) -> some View {
        HStack(spacing: 24) {
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

            AirPlayButton()
                .frame(width: 32, height: 32)
                .accessibilityLabel("AirPlay")

            Button {
                showAddToPlaylist = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Add to playlist")
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showAddToPlaylist) {
            AddItemToPlaylistSheet(track: track)
                .environmentObject(playlistVM)
                .environmentObject(playerVM)
        }
    }

    @ViewBuilder
    private func archiveLink(for track: Track) -> some View {
        let identifier = track.parentIdentifier ?? track.id
        let cleanId = identifier.contains("/")
            ? String(identifier.split(separator: "/").first ?? "")
            : identifier
        if let url = URL(string: "https://archive.org/details/\(cleanId)") {
            Link(destination: url) {
                Image(systemName: "safari")
                    .font(.body)
            }
            .accessibilityLabel("View on archive.org")
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            Button("15 min") { playerVM.startSleepTimer(minutes: 15) }
            Button("30 min") { playerVM.startSleepTimer(minutes: 30) }
            Button("45 min") { playerVM.startSleepTimer(minutes: 45) }
            Button("60 min") { playerVM.startSleepTimer(minutes: 60) }
            Divider()
            Button("End of Track") { playerVM.setSleepAtEndOfTrack(true) }
            if playerVM.isSleepTimerActive {
                Divider()
                Button("Cancel Timer", role: .destructive) {
                    playerVM.cancelSleepTimer()
                }
            }
        } label: {
            Image(systemName: playerVM.isSleepTimerActive
                  ? "moon.zzz.fill" : "moon.zzz")
                .font(.body)
        }
    }
}

private struct ShuffleControl: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var body: some View {
        Button {
            playerVM.toggleShuffle()
        } label: {
            Image(systemName: playerVM.shuffleMode ? "shuffle" : "shuffle")
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
            Image(systemName: playerVM.repeatMode == .one ? "repeat.1" : "repeat")
                .font(.caption)
                .foregroundStyle(playerVM.repeatMode == .one ? .blue : .secondary)
        }
    }
}
