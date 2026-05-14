import SwiftUI

struct iPodView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @State private var pendingChannel: Channel = {
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
    @State private var showMoreOptions = false
    @State private var isFavorite = false

    private var displayChannel: Channel {
        playerVM.currentChannel ?? pendingChannel
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Device body — slate blue-grey
                Color(red: 0.290, green: 0.333, blue: 0.408)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Screen panel — top portion
                    screenPanel
                        .frame(height: geo.size.height * 0.50)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    Spacer(minLength: 8)

                    // Click wheel — bottom portion
                    ClickWheel(
                        isPlaying: playerVM.isPlaying,
                        onMenu:      { showMainMenu = true },
                        onBack:      { playerVM.back() },
                        onForward:   { playerVM.skip() },
                        onPlayPause: { playerVM.togglePlayPause() }
                    )
                    .frame(width: min(geo.size.width * 0.85, 300),
                           height: min(geo.size.width * 0.85, 300))

                    Spacer(minLength: 12)
                }
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
        .sheet(isPresented: $showMoreOptions) {
            moreOptionsSheet
        }
        .onChange(of: playerVM.currentTrack?.id) { _, _ in
            refreshFavoriteState()
        }
        .task {
            await playlistVM.loadPlaylists()
            let wasPlaying = UserDefaults.standard.bool(forKey: "wasPlayingOnQuit")
            UserDefaults.standard.removeObject(forKey: "wasPlayingOnQuit")
            await playerVM.load(channel: pendingChannel, autoPlay: wasPlaying)
        }
    }

    // MARK: - Screen Panel

    private var screenPanel: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed album art background
            artworkBackground

            // Dark gradient overlay for text legibility
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                // Channel name / description — top of screen
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayChannel.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.9))
                            .animation(.spring(duration: 0.25), value: displayChannel.id)
                        if !playerVM.channelDescription.isEmpty {
                            Text(playerVM.channelDescription)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                                .animation(.spring(duration: 0.25), value: playerVM.channelDescription)
                        }
                    }
                    Spacer()
                    // Info button
                    Button { showAbout = true } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer()

                // Track metadata — bottom section above scrubber
                if let track = playerVM.currentTrack {
                    trackMetadataStack(track: track)
                } else if playerVM.isLoading {
                    loadingView
                } else if let err = playerVM.errorMessage {
                    errorView(err)
                } else {
                    idleView
                }

                // Scrubber row
                scrubberRow
                    .padding(.bottom, 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .onTapGesture {
            if playerVM.currentTrack != nil { showTrackDetail = true }
        }
        .contextMenu {
            if let track = playerVM.currentTrack {
                Button { showAddToPlaylist = true } label: {
                    Label("Add to Playlist", systemImage: "plus.circle")
                }
                Button {
                    Task { await offlineService.makeOffline(channel: displayChannel) }
                } label: {
                    Label("Download Channel", systemImage: "arrow.down.circle")
                }
                Button { showTrackDetail = true; _ = track } label: {
                    Label("Track Details", systemImage: "info.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var artworkBackground: some View {
        if let art = playerVM.currentArtwork {
            Image(uiImage: art)
                .resizable()
                .scaledToFill()
                .animation(.easeInOut(duration: 0.8), value: playerVM.currentTrack?.id)
        } else {
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [categoryColor(for: displayChannel.category).opacity(0.6),
                                     categoryColor(for: displayChannel.category).opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: displayChannel.icon)
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    @ViewBuilder
    private func trackMetadataStack(track: Track) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            if playerVM.isLoading, let msg = playerVM.loadingMessage {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(.white)
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Text(track.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(track.artist)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)

            if let part = track.partNumber, let total = track.totalParts, total > 1 {
                Text("Part \(part) of \(total)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }

            licenseRow(track.license, source: track.source)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white)
            Text(playerVM.loadingMessage ?? "Loading…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.trailing)
            Button("Try Again") {
                if let ch = playerVM.currentChannel {
                    Task { await playerVM.load(channel: ch) }
                }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var idleView: some View {
        Text("Tap \(Image(systemName: "line.3.horizontal")) to select a channel")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }

    private var scrubberRow: some View {
        VStack(spacing: 4) {
            if let dur = playerVM.trackDuration, dur > 0 {
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
                .tint(playerVM.artworkDominantColor)
                .padding(.horizontal, 14)

                HStack {
                    Text(formatTime(playerVM.currentPosition))
                    Spacer()
                    Text("-\(formatTime(max(0, dur - playerVM.currentPosition)))")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .padding(.horizontal, 14)
            }

            HStack(spacing: 0) {
                // Star / Favorites
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundStyle(isFavorite ? .yellow : .white.opacity(0.7))
                }
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                .padding(.leading, 14)

                Spacer()

                // More options (•••)
                Button { showMoreOptions = true } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityLabel("More Options")
                .padding(.trailing, 14)
            }
            .padding(.top, playerVM.trackDuration != nil ? 4 : 0)
        }
    }

    // MARK: - More Options Sheet

    private var moreOptionsSheet: some View {
        NavigationStack {
            List {
                Section("Playback") {
                    Button {
                        playerVM.toggleShuffle()
                    } label: {
                        Label(
                            playerVM.shuffleMode ? "Shuffle: On" : "Shuffle: Off",
                            systemImage: "shuffle"
                        )
                        .foregroundStyle(playerVM.shuffleMode ? .tint : .primary)
                    }

                    Button {
                        playerVM.toggleRepeat()
                    } label: {
                        Label(
                            playerVM.repeatMode == .off ? "Repeat: Off" : "Repeat: One",
                            systemImage: playerVM.repeatMode == .off ? "repeat" : "repeat.1"
                        )
                        .foregroundStyle(playerVM.repeatMode == .off ? .primary : .tint)
                    }
                }

                if playerVM.currentTrack != nil {
                    Section("Track") {
                        Button {
                            showMoreOptions = false
                            showAddToPlaylist = true
                        } label: {
                            Label("Add to Playlist", systemImage: "plus.circle")
                        }

                        Button {
                            showMoreOptions = false
                            Task { await offlineService.makeOffline(channel: displayChannel) }
                        } label: {
                            Label("Download Channel", systemImage: "arrow.down.circle")
                        }

                        Button {
                            showMoreOptions = false
                            showTrackDetail = true
                        } label: {
                            Label("Track Details", systemImage: "info.circle")
                        }
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showMoreOptions = false }
                }
            }
        }
    }

    // MARK: - Helpers

    private func categoryColor(for category: String) -> Color {
        switch category {
        case "Classical":    return Color(red: 0.42, green: 0.20, blue: 0.80)
        case "Audiobooks":   return Color(red: 0.55, green: 0.35, blue: 0.10)
        case "Contemporary": return Color(red: 0.20, green: 0.40, blue: 0.20)
        case "Lectures":     return Color(red: 0.00, green: 0.13, blue: 0.28)
        case "News":         return Color(red: 0.10, green: 0.20, blue: 0.40)
        case "Ambient":      return Color(red: 0.08, green: 0.38, blue: 0.28)
        default:             return Color(red: 0.20, green: 0.25, blue: 0.35)
        }
    }

    @ViewBuilder
    private func licenseRow(_ license: LicenseType, source: String) -> some View {
        HStack(spacing: 4) {
            switch license {
            case .cc0:          screenBadge("CC0")
            case .ccBy:         screenBadge("CC BY")
            case .publicDomain: screenBadge("PD")
            case .rejected:     EmptyView()
            }
            switch source {
            case "musopen":         screenBadge("Musopen")
            case "oxford_lectures": screenBadge("Oxford")
            case "podcast":         screenBadge("Podcast")
            case "nps":             screenBadge("NPS")
            default:                screenBadge("Archive.org")
            }
        }
    }

    private func screenBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.white.opacity(0.15))
            .foregroundStyle(.white.opacity(0.85))
            .clipShape(Capsule())
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
            let innerR  = size * 0.225
            let midRing = (outerR + innerR) / 2

            ZStack {
                // Outer ring — charcoal
                Circle()
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.11))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                // Subtle inner highlight ring
                Circle()
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)

                // Center button — slightly lighter charcoal
                Circle()
                    .fill(Color(red: 0.14, green: 0.14, blue: 0.15))
                    .frame(width: innerR * 2, height: innerR * 2)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .allowsHitTesting(false)

                // MENU icon (top)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(y: -midRing)
                    .allowsHitTesting(false)

                // Back (left)
                Image(systemName: "backward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(x: -midRing)
                    .allowsHitTesting(false)

                // Forward (right)
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(x: midRing)
                    .allowsHitTesting(false)

                // Play/Pause (bottom)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
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
