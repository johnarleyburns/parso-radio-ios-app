import SwiftUI

struct NowPlayingSheet: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showAddToPlaylist = false
    @State private var showAlbumTracks = false

    private var behavior: PlaybackBehavior {
        playerVM.currentChannel?.behavior ?? MediaKind.music.behavior
    }

    private var channelCategory: String {
        playerVM.currentChannel?.category ?? ""
    }

    var body: some View {
        ZStack {
            if let channel = playerVM.currentChannel,
               channel.mediaKind == .ambient {
                if let videoURL = AmbientStaticService.bundledVideoURL(forChannelId: channel.id) {
                    LoopingVideoView(url: videoURL, isPlaying: playerVM.isPlaying)
                        .ignoresSafeArea()
                } else {
                    ProceduralVisualizerView(
                        seed: channel.id,
                        isPlaying: playerVM.isPlaying
                    )
                    .ignoresSafeArea()
                }
            }

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
            } else if let channel = playerVM.currentChannel,
                      let channelImage = UIImage(named: channel.id) {
                Image(uiImage: channelImage)
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
    private var bottomControls: some View {
        let b = behavior
        let tint = ChannelCategoryStyle.color(for: channelCategory)
        let track = playerVM.currentTrack
        let controlsDisabled = track == nil || playerVM.isLoading

        VStack(spacing: 8) {
            stableProgressSection(track: track, tint: tint, disabled: controlsDisabled)

            TransportControls()
                .disabled(controlsDisabled)

            HStack(spacing: 0) {
                ShuffleControl()
                    .disabled(controlsDisabled || !b.allowsShuffleToggle)
                    .opacity(b.allowsShuffleToggle ? 1 : 0.3)
                Spacer()

                HStack(spacing: 16) {
                    if let t = track, t.source == "internet_archive" {
                        archiveLink(for: t)
                    } else {
                        Image(systemName: "safari")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .opacity(0.3)
                    }
                    AirPlayButton()
                        .frame(width: 28, height: 28)
                    Button {
                        showAddToPlaylist = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.body)
                    }
                    .disabled(controlsDisabled)
                    .accessibilityLabel("Add to playlist")
                    Button {
                        showAlbumTracks = true
                    } label: {
                        Image(systemName: "opticaldisc")
                            .font(.body)
                            .foregroundStyle(playerVM.currentTrackIsMultiPart ? .primary : .secondary)
                            .opacity(playerVM.currentTrackIsMultiPart ? 1 : 0.3)
                    }
                    .disabled(!playerVM.currentTrackIsMultiPart)
                    .accessibilityLabel("View album tracks")
                    sleepTimerMenu
                        .disabled(controlsDisabled || !b.supportsSleepTimer)
                        .opacity(b.supportsSleepTimer ? 1 : 0.3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)

                Spacer()
                RepeatControl()
                    .disabled(controlsDisabled || !b.allowsShuffleToggle)
                    .opacity(b.allowsShuffleToggle ? 1 : 0.3)
            }
            .sheet(isPresented: $showAddToPlaylist) {
                if let t = track {
                    AddItemToPlaylistSheet(track: t)
                        .environmentObject(playlistVM)
                        .environmentObject(playerVM)
                }
            }
            .sheet(isPresented: $showAlbumTracks) {
                if let t = track {
                    AlbumTracksSheet(track: t)
                        .environmentObject(playerVM)
                }
            }

            let cols = [GridItem(.adaptive(minimum: 76), spacing: 12)]
            LazyVGrid(columns: cols, spacing: 12) {
                SpeedControl(showLabel: false)
                    .disabled(controlsDisabled || !b.supportsSpeedControl)
                    .opacity(b.supportsSpeedControl ? 1 : 0.3)
                ChapterButton(showLabel: false)
                    .disabled(controlsDisabled || !b.supportsChapters)
                    .opacity(b.supportsChapters ? 1 : 0.3)
                BookmarkButton(showLabel: false)
                    .disabled(controlsDisabled || !b.supportsBookmarks)
                    .opacity(b.supportsBookmarks ? 1 : 0.3)
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func stableProgressSection(track: Track?, tint: Color, disabled: Bool) -> some View {
        let fid = track.map { $0.favoriteID(for: $0.favoriteKind(channel: playerVM.currentChannel)) }
        let isFav = fid.map { id in favorites.favorites.contains { $0.id == id } } ?? false
        let remaining = (playerVM.trackDuration ?? 0) - playerVM.currentPosition
        let b = behavior

        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    Button {
                        if let t = track {
                            Task {
                                await favorites.toggle(track: t, channel: playerVM.currentChannel,
                                                       positionSeconds: playerVM.currentPosition)
                            }
                        }
                    } label: {
                        Image(systemName: isFav ? "heart.fill" : "heart")
                            .font(.body)
                            .foregroundStyle(isFav ? .red : .secondary)
                    }
                    .disabled(disabled)
                    .accessibilityLabel(isFav ? "Remove from favorites" : "Add to favorites")
                    .padding(.bottom, 8)

                    Text(playerVM.currentPosition.formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                if b.supportsBookSkip, let timeLeft = playerVM.timeLeftInBook {
                    let noun = playerVM.currentChannel?.mediaKind == .lecture ? "series" : "book"
                    Text("Time left in \(noun): \(timeLeft.formattedTime)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()
                }

                VStack(spacing: 8) {
                    if let t = track, let shareURL = ShareURLBuilder.url(for: t) {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body)
                        }
                        .accessibilityLabel("Share")
                        .padding(.bottom, 8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .opacity(0.3)
                            .padding(.bottom, 8)
                    }

                    Text("-\(remaining.formattedTime)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)

            ScrubBar(tint: tint)
                .disabled(disabled)
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

private struct AlbumTracksSheet: View {
    let track: Track
    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var parts: [Track] = []
    @State private var isLoading = true

    private var identifier: String { track.parentIdentifier ?? track.id }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            await playerVM.playEntireCurrentItem()
                            dismiss()
                        }
                    } label: {
                        Label("Play Entire Album", systemImage: "play.fill")
                    }
                }

                Section {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if parts.isEmpty {
                        Text("No tracks found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(parts.enumerated()), id: \.1.id) { idx, part in
                            HStack {
                                Text("\(idx + 1). \(part.title)")
                                    .lineLimit(2)
                                Spacer()
                                if part.id == playerVM.currentTrack?.id {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Album Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                parts = await playerVM.resolveItemParts(identifier: identifier) ?? []
                isLoading = false
            }
        }
    }
}
