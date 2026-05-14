import SwiftUI

struct iPodView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @State private var pendingChannel: Channel = {
        // UC2: restore the last-used channel between app launches.
        let lastId = UserDefaults.standard.string(forKey: "lastChannelId") ?? "bach"
        return Channel.defaults.first { $0.id == lastId } ?? Channel.defaults[0]
    }()
    @State private var showChannelSelector = false
    @State private var showAbout = false
    @State private var showTrackDetail = false
    @State private var showMainMenu = false
    @State private var showPlaylists = false
    @State private var showSearch = false
    @State private var showAddToPlaylist = false
    @State private var isFavorite = false

    private var displayChannel: Channel {
        playerVM.currentChannel ?? pendingChannel
    }

    var body: some View {
        ZStack {
            // Ambient art background
            if let artwork = playerVM.currentArtwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 40)
                    .opacity(0.25)
                    .animation(.easeInOut(duration: 1.0), value: playerVM.currentTrack?.id)
            } else {
                Color(.systemGroupedBackground).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                channelLabel
                    .padding(.top, 20)

                Spacer(minLength: 16)

                ClickWheel(
                    isPlaying: playerVM.isPlaying,
                    onMenu:      { showMainMenu = true },
                    onBack:      { playerVM.back() },
                    onForward:   { playerVM.skip() },
                    onPlayPause: { playerVM.togglePlayPause() }
                )
                .frame(width: 280, height: 280)

                // Shuffle / Repeat / Favorites row
                HStack(spacing: 24) {
                    Button {
                        playerVM.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 17))
                            .foregroundStyle(playerVM.shuffleMode ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                    .accessibilityLabel(playerVM.shuffleMode ? "Shuffle On" : "Shuffle Off")

                    // Book navigation (Librivox / audiobooks)
                    Button {
                        Task { await playerVM.skipToPreviousBook() }
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Previous Book")

                    Button {
                        Task { await playerVM.skipToNextBook() }
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Next Book")

                    Button {
                        playerVM.toggleRepeat()
                    } label: {
                        Image(systemName: playerVM.repeatMode == .off ? "repeat" : "repeat.1")
                            .font(.system(size: 17))
                            .foregroundStyle(playerVM.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    }
                    .accessibilityLabel(playerVM.repeatMode == .off ? "Repeat Off" : "Repeat One")

                    Button {
                        toggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 17))
                            .foregroundStyle(isFavorite ? .red : .secondary)
                    }
                    .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                }
                .padding(.top, 14)

                Spacer(minLength: 14)

                // UC9: tap the card to see full track details.
                nowPlayingCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                    .onTapGesture {
                        if playerVM.currentTrack != nil { showTrackDetail = true }
                    }
                    .contextMenu {
                        if let track = playerVM.currentTrack {
                            Button {
                                showAddToPlaylist = true
                            } label: {
                                Label("Add to Playlist", systemImage: "plus.circle")
                            }
                            Button {
                                Task { await offlineService.makeOffline(channel: displayChannel) }
                            } label: {
                                Label("Download Channel", systemImage: "arrow.down.circle")
                            }
                            Button {
                                showTrackDetail = true
                                _ = track
                            } label: {
                                Label("Track Details", systemImage: "info.circle")
                            }
                        }
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showAbout = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .sheet(isPresented: $showMainMenu) {
            MainMenuView(
                displayChannel: displayChannel,
                onSelectChannel: {
                    showMainMenu = false
                    showChannelSelector = true
                },
                onOpenPlaylists: {
                    showMainMenu = false
                    showPlaylists = true
                },
                onOpenSearch: {
                    showMainMenu = false
                    showSearch = true
                },
                onDownloadChannel: {
                    showMainMenu = false
                    Task { await offlineService.makeOffline(channel: displayChannel) }
                },
                onOpenAbout: {
                    showMainMenu = false
                    showAbout = true
                }
            )
        }
        .sheet(isPresented: $showChannelSelector) {
            ChannelSelectorView(currentChannelId: displayChannel.id) { channel in
                pendingChannel = channel
                showChannelSelector = false
                Task { await playerVM.load(channel: channel) }
            }
        }
        .sheet(isPresented: $showPlaylists) {
            PlaylistListView()
                .environmentObject(playlistVM)
                .environmentObject(playerVM)
                .environmentObject(offlineService)
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
                .environmentObject(playlistVM)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(isPresented: $showTrackDetail) {
            if let track = playerVM.currentTrack {
                TrackDetailView(track: track)
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let track = playerVM.currentTrack {
                AddToPlaylistSheet(track: track)
                    .environmentObject(playlistVM)
            }
        }
        .onChange(of: playerVM.currentTrack?.id) { _, _ in
            refreshFavoriteState()
        }
        .task {
            let wasPlaying = UserDefaults.standard.bool(forKey: "wasPlayingOnQuit")
            UserDefaults.standard.removeObject(forKey: "wasPlayingOnQuit")
            await playerVM.load(channel: pendingChannel, autoPlay: wasPlaying)
        }
    }

    // MARK: - Channel label

    private var channelLabel: some View {
        VStack(spacing: 3) {
            Text(displayChannel.name)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .animation(.spring(duration: 0.25), value: displayChannel.id)
            Text(displayChannel.category)
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.spring(duration: 0.25), value: displayChannel.category)
            if !playerVM.channelDescription.isEmpty {
                Text(playerVM.channelDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 1)
                    .animation(.spring(duration: 0.25), value: playerVM.channelDescription)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Now-playing card

    @ViewBuilder
    private var nowPlayingCard: some View {
        if let track = playerVM.currentTrack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    channelArtwork
                        .opacity(playerVM.isLoading ? 0.6 : 1)
                        .animation(.easeInOut(duration: 0.25), value: playerVM.isLoading)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if playerVM.isLoading, let msg = playerVM.loadingMessage {
                            HStack(spacing: 5) {
                                ProgressView().scaleEffect(0.65)
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        } else {
                            licenseRow(track.license, source: track.source)
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 0)
                }

                if let dur = playerVM.trackDuration, dur > 0 {
                    VStack(spacing: 3) {
                        Slider(
                            value: Binding(
                                get: { playerVM.currentPosition },
                                set: { playerVM.currentPosition = $0 }
                            ),
                            in: 0...max(dur, 1),
                            onEditingChanged: { editing in
                                playerVM.isScrubbing = editing
                                if !editing { playerVM.seek(to: playerVM.currentPosition) }
                            }
                        )
                        .tint(progressTint(for: displayChannel.category))
                        HStack {
                            Text(formatTime(playerVM.currentPosition))
                            Spacer()
                            Text(formatTime(dur))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    .padding(.top, 10)
                }
            }
            .padding(14)
            .background(
                Color(.secondarySystemGroupedBackground).opacity(playerVM.currentArtwork != nil ? 0.85 : 1.0),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        } else if playerVM.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text(playerVM.loadingMessage ?? "Loading…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        } else if let err = playerVM.errorMessage {
            VStack(spacing: 10) {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    if let ch = playerVM.currentChannel {
                        Task { await playerVM.load(channel: ch) }
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        } else {
            // Placeholder before first load
            HStack(spacing: 12) {
                channelArtwork
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    +
                    Text(" ")
                    +
                    Text(Image(systemName: "line.3.horizontal"))
                        .font(.subheadline)
                    +
                    Text(" to select a channel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var channelArtwork: some View {
        ZStack {
            if let artwork = playerVM.currentArtwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(categoryGradient(for: displayChannel.category))
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                Image(systemName: displayChannel.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(playerVM.isPlaying ? 1.05 : 1.0)
        .animation(
            playerVM.isPlaying
                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                : .default,
            value: playerVM.isPlaying
        )
    }

    @ViewBuilder
    private func licenseRow(_ license: LicenseType, source: String) -> some View {
        HStack(spacing: 6) {
            switch license {
            case .cc0:          badge("CC0", color: .blue)
            case .ccBy:         badge("CC BY", color: .orange)
            case .publicDomain: badge("Public Domain", color: .green)
            case .rejected:     EmptyView()
            }
            switch source {
            case "fma":              badge("FMA", color: .gray)
            case "musopen":          badge("Musopen", color: .purple)
            case "oxford_lectures":  badge("Oxford", color: Color(red: 0.00, green: 0.13, blue: 0.28))
            case "podcast":          badge("Podcast", color: Color(red: 0.10, green: 0.20, blue: 0.40))
            case "nps":              badge("NPS", color: Color(red: 0.08, green: 0.38, blue: 0.28))
            case "freesound":        badge("Freesound", color: Color(red: 0.08, green: 0.38, blue: 0.28))
            default:                 badge("Archive.org", color: .gray)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func progressTint(for category: String) -> Color {
        switch category {
        case "Classical":    return Color(red: 0.42, green: 0.20, blue: 0.80)
        case "Audiobooks":   return Color(red: 0.55, green: 0.35, blue: 0.10)
        case "Contemporary": return Color(red: 0.20, green: 0.40, blue: 0.20)
        case "Lectures":     return Color(red: 0.00, green: 0.13, blue: 0.28)
        case "News":         return Color(red: 0.10, green: 0.20, blue: 0.40)
        case "Ambient":      return Color(red: 0.08, green: 0.38, blue: 0.28)
        default:             return .accentColor
        }
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: - Favorites helpers

    private func refreshFavoriteState() {
        guard let track = playerVM.currentTrack else {
            isFavorite = false
            return
        }
        Task {
            let fav = await playlistVM.isInFavorites(track)
            await MainActor.run { isFavorite = fav }
        }
    }

    private func toggleFavorite() {
        guard let track = playerVM.currentTrack else { return }
        Task {
            await playlistVM.toggleFavorite(track)
            let fav = await playlistVM.isInFavorites(track)
            await MainActor.run { isFavorite = fav }
        }
    }
}

// MARK: - Click Wheel

struct ClickWheel: View {
    let isPlaying: Bool
    let onMenu:      () -> Void
    let onBack:      () -> Void
    let onForward:   () -> Void
    let onPlayPause: () -> Void

    @State private var tapTrigger = 0

    var body: some View {
        GeometryReader { geo in
            let size    = min(geo.size.width, geo.size.height)
            let outerR  = size / 2
            let innerR  = size * 0.225   // center button radius ≈ 45% of total diameter
            let midRing = (outerR + innerR) / 2   // label placement

            ZStack {
                // Outer ring
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

                // Inner clickable circle
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: innerR * 2, height: innerR * 2)
                    .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
                    .allowsHitTesting(false)

                // MENU icon (top)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .offset(y: -midRing)
                    .allowsHitTesting(false)

                // Back (left)
                Image(systemName: "backward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .offset(x: -midRing)
                    .allowsHitTesting(false)

                // Forward (right)
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .offset(x: midRing)
                    .allowsHitTesting(false)

                // Play/Pause (bottom)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .offset(y: midRing)
                    .allowsHitTesting(false)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .sensoryFeedback(.impact(weight: .light), trigger: tapTrigger)
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        let dist = sqrt(dx * dx + dy * dy)

                        // Must be within the outer ring but outside the inner center button
                        guard dist <= outerR, dist > innerR else { return }

                        tapTrigger += 1
                        if abs(dy) >= abs(dx) {
                            if dy < 0 { onMenu() } else { onPlayPause() }
                        } else {
                            if dx < 0 { onBack() } else { onForward() }
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback Controls")
            .accessibilityAction(.default) { onPlayPause() }
            .accessibilityAction(named: "Menu — Open Menu") { onMenu() }
            .accessibilityAction(named: "Back") { onBack() }
            .accessibilityAction(named: "Forward") { onForward() }
        }
    }
}

#Preview {
    let db = try! DatabaseService(path: ":memory:")
    let dm = DownloadManager(db: db)
    iPodView()
        .environmentObject(PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: AudioPlayerService(),
            downloadManager: dm
        ))
        .environmentObject(PlaylistViewModel(db: db))
        .environmentObject(OfflineDownloadService(db: db, downloadManager: dm))
}
