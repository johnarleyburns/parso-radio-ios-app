import SwiftUI

struct iPodView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @State private var pendingChannel: Channel = {
        let lastId = UserDefaults.standard.string(forKey: "lastChannelId") ?? "spanish-guitar"
        return Channel.defaults.first { $0.id == lastId } ?? Channel.defaults[0]
    }()
    @State private var showChannelSelector = false
    @State private var showAbout = false
    @State private var showMainMenu = false
    @State private var showPlaylists = false
    @State private var showSearch = false
    @State private var showAddToPlaylist = false
    @State private var showAddItemToPlaylist = false
    @State private var showMoreOptions = false
    @State private var showFullMetadata = false
    @State private var isFavorite = false

    private var displayChannel: Channel {
        playerVM.currentChannel ?? pendingChannel
    }

    // A looping ambient channel is a single track that repeats forever:
    // transport / scrubber / favorites / shuffle / repeat make no sense, so
    // the UI collapses to "now playing + info" only.
    private var isAmbientLoop: Bool {
        playerVM.currentChannel?.contentType == .ambientLoop
    }

    // Bundled looping backdrop for the current ambient channel, if any.
    private var ambientVideoURL: URL? {
        guard isAmbientLoop else { return nil }
        return AmbientStaticService.bundledVideoURL(
            forChannelId: playerVM.currentChannel?.id ?? "")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Device body — slate blue-grey
                Color(red: 0.290, green: 0.333, blue: 0.408)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Screen panel — top portion. The VStack respects the top
                    // safe area, so the panel starts just below the status bar;
                    // a top margin equal to the side margin then offsets it.
                    // Floor at 160 pt: GeometryReader can report geo.size = (0,0)
                    // on the first layout pass before the view is measured,
                    // which would collapse the panel and overflow its content.
                    // No top margin: the panel sits flush just below the
                    // status bar (the VStack still respects the top safe area).
                    screenPanel
                        .frame(height: max(160.0, geo.size.height * 0.50))
                        .padding(.horizontal, deviceMargin(geo))

                    // Two equal spacers center the wheel between the track box
                    // and the physical screen bottom. minLength guarantees the
                    // track→wheel gap is at least the side margin.
                    Spacer(minLength: deviceMargin(geo))

                    ClickWheel(
                        isPlaying: playerVM.isPlaying,
                        currentTime: playerVM.currentPosition,
                        // Ambient loops: force 0 so the progress arc/thumb
                        // band never appears (the bundled WAV has a finite
                        // duration that would otherwise light it up).
                        duration: isAmbientLoop ? 0 : (playerVM.trackDuration ?? 0),
                        transportEnabled: !isAmbientLoop,
                        onSeek: { playerVM.seek(to: $0) },
                        onScrubChanged: { playerVM.isScrubbing = $0 },
                        onMenu:      { showMainMenu = true },
                        onBack:      { playerVM.back() },
                        onForward:   { playerVM.skip() },
                        onPlayPause: { playerVM.togglePlayPause() }
                    )
                    .frame(width: wheelDiameter(geo), height: wheelDiameter(geo))

                    Spacer(minLength: deviceMargin(geo))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Match the device-body Color: extend to the physical screen
                // bottom so the bottom spacer (and thus the wheel centering)
                // is measured to the real screen edge, not the safe-area inset
                // — otherwise the wheel looks bottom-heavy.
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .sheet(isPresented: $showMainMenu) {
            MainMenuView(
                onSelectChannel: { channel in
                    pendingChannel = channel
                    showMainMenu = false
                    Task { await playerVM.load(channel: channel) }
                },
                dismissAll: { showMainMenu = false }
            )
            .environmentObject(playlistVM)
            .environmentObject(playerVM)
            .environmentObject(offlineService)
        }
        .sheet(isPresented: $showChannelSelector) {
            ChannelSelectorView(currentChannelId: displayChannel.id) { channel in
                pendingChannel = channel
                showChannelSelector = false
                Task { await playerVM.load(channel: channel) }
            }
        }
        .sheet(isPresented: $showPlaylists) {
            PlaylistListView(dismissAll: { showPlaylists = false })
                .environmentObject(playlistVM)
                .environmentObject(playerVM)
                .environmentObject(offlineService)
        }
        .sheet(isPresented: $showSearch) {
            SearchView(dismissAll: { showSearch = false })
                .environmentObject(playlistVM)
                .environmentObject(playerVM)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let track = playerVM.currentTrack {
                AddToPlaylistSheet(track: track)
                    .environmentObject(playlistVM)
            }
        }
        .sheet(isPresented: $showAddItemToPlaylist) {
            if let track = playerVM.currentTrack {
                AddItemToPlaylistSheet(track: track)
                    .environmentObject(playlistVM)
                    .environmentObject(playerVM)
            }
        }
        .sheet(isPresented: $showMoreOptions) {
            combinedTrackSheet
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

            // Top scrim — keeps the channel title readable over light artwork.
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .center
            )

            // Bottom scrim for the track metadata / scrubber legibility.
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                // Playlist or channel name only. NO stale fallback to the
                // last-selected channel: a search-result/standalone play has
                // neither, so the label stays blank until real content shows.
                HStack {
                    Text(playerVM.currentPlaylist?.name
                         ?? playerVM.currentChannel?.name ?? "")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.95))
                        .contentShape(Rectangle())
                        // Tapping the playlist/channel name opens the menu
                        // (not track info — that's the rest of the panel / •••).
                        .onTapGesture { showMainMenu = true }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer()

                // Track metadata — bottom section above scrubber.
                // currentTrack is nil on error (playTrack catch clears it), so
                // errorView is reached naturally without reordering these branches.
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
            if playerVM.currentTrack != nil { showMoreOptions = true }
        }
        .contextMenu {
            if playerVM.currentTrack != nil, !isAmbientLoop {
                Button { showAddToPlaylist = true } label: {
                    Label("Add to Playlist", systemImage: "plus.circle")
                }
            }
        }
    }

    private var artworkBackground: some View {
        // Rectangle takes EXACTLY the proposed size and never overflows, so it
        // — not the artwork — determines this view's layout size. The image is an
        // .overlay, which by SwiftUI's rules does not influence the host's size.
        // .scaledToFill() on the overlay still overflows visually, but .clipped()
        // trims it to the Rectangle's bounds. This is why an earlier
        // `.frame(maxWidth: .infinity).clipped()` did NOT work: an infinite max
        // lets scaledToFill's oversized dimension pass through as the reported
        // layout width, inflating the screen panel and pushing the wheel offscreen.
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [categoryColor(for: displayChannel.category).opacity(0.6),
                             categoryColor(for: displayChannel.category).opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if isAmbientLoop, let video = ambientVideoURL {
                    // Rainy Day: user prefers the right edge of the clip.
                    LoopingVideoView(
                        url: video,
                        horizontalAnchor:
                            playerVM.currentChannel?.id == "ambient-rain" ? 1.0 : 0.5)
                } else if let art = playerVM.currentArtwork {
                    Image(uiImage: art)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: displayChannel.icon)
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.8), value: playerVM.currentTrack?.id)
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

            if let artist = cleaned(track.artist) {
                Text(artist)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            if let part = track.partNumber, let total = track.totalParts, total > 1 {
                Text("Part \(part) of \(total)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }

            // News episodes: show the publish date on the now-playing line
            // (this single-track screen IS the news "listing").
            if playerVM.currentChannel?.preferredSource == "podcast",
               let date = track.bestDate {
                Text(date.formatted(.dateTime.year().month().day()))
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

    // The scrub bar is gone — the click wheel arc IS the position display.
    // Bottom control row: Favorites · elapsed | Shuffle Repeat | remaining · More.
    // Ambient-loop channels collapse this to just the info (•••) button —
    // a single forever-repeating track has nothing to favorite/shuffle/seek.
    @ViewBuilder
    private var scrubberRow: some View {
        if isAmbientLoop {
            HStack(spacing: 0) {
                Spacer()
                Button { showMoreOptions = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityLabel("Track Info")
                .padding(.trailing, 14)
            }
            .padding(.vertical, 4)
        } else {
            fullScrubberRow
        }
    }

    private var fullScrubberRow: some View {
        HStack(spacing: 0) {
            Button { toggleFavorite() } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(isFavorite ? .red : .white.opacity(0.7))
            }
            .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .padding(.leading, 14)

            if let dur = playerVM.trackDuration, dur > 0 {
                Text(formatTime(playerVM.currentPosition))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.leading, 8)
                    .accessibilityLabel("Elapsed time")
            }

            Spacer()

            Button { playerVM.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 16))
                    .foregroundStyle(playerVM.shuffleMode ? .white : .white.opacity(0.4))
            }
            .accessibilityLabel(playerVM.shuffleMode ? "Shuffle On" : "Shuffle Off")
            .padding(.horizontal, 18)

            Button { playerVM.toggleRepeat() } label: {
                Image(systemName: playerVM.repeatMode == .off ? "repeat" : "repeat.1")
                    .font(.system(size: 16))
                    .foregroundStyle(playerVM.repeatMode == .off ? .white.opacity(0.4) : .white)
            }
            .accessibilityLabel(playerVM.repeatMode == .off ? "Repeat Off" : "Repeat One")
            .padding(.trailing, 18)

            Spacer()

            if let dur = playerVM.trackDuration, dur > 0 {
                Text("-" + formatTime(max(0, dur - playerVM.currentPosition)))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.trailing, 8)
                    .accessibilityLabel("Remaining time")
            }

            Button { showMoreOptions = true } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityLabel("More Options")
            .padding(.trailing, 14)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Combined Track Info + Options sheet

    private var combinedTrackSheet: some View {
        NavigationStack {
            List {
                if let track = playerVM.currentTrack {
                    Section("Now Playing") {
                        infoRow("Title", track.title)
                        if let a = cleaned(track.artist) { infoRow("Artist", a) }
                        if let c = cleaned(track.composer) { infoRow("Composer", c.capitalized) }
                        if let dur = trackInfoDuration(track) {
                            infoRow("Duration", formatTime(dur))
                        }
                        if let date = track.bestDate {
                            infoRow(track.dateLabel,
                                    date.formatted(.dateTime.year().month().day()))
                        }
                        DisclosureGroup("Full Metadata", isExpanded: $showFullMetadata) {
                            ForEach(fullMetadata(track), id: \.0) { pair in
                                infoRow(pair.0, pair.1)
                            }
                        }
                    }

                    // Ambient loops are info-only: no playlist actions.
                    if !isAmbientLoop {
                        Section {
                            Button {
                                showMoreOptions = false
                                showAddToPlaylist = true
                            } label: {
                                Label("Add to Playlist", systemImage: "plus.circle")
                            }
                            if playerVM.currentTrackIsMultiPart {
                                Button {
                                    showMoreOptions = false
                                    showAddItemToPlaylist = true
                                } label: {
                                    Label("Add \(itemKindLabel(track)) to Playlist",
                                          systemImage: "text.badge.plus")
                                }
                                Button {
                                    showMoreOptions = false
                                    let nm = playerVM.itemDisplayName(for: track)
                                    Task {
                                        await playerVM.addEntireItemToNewPlaylist(
                                            from: track, named: nm, using: playlistVM)
                                    }
                                } label: {
                                    Label(
                                        "Add \(itemKindLabel(track)) to New Playlist “\(shortName(playerVM.itemDisplayName(for: track)))”",
                                        systemImage: "rectangle.stack.badge.plus")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showMoreOptions = false }
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func licenseName(_ l: LicenseType) -> String {
        switch l {
        case .cc0:          return "CC0"
        case .ccBy:         return "CC BY"
        case .publicDomain: return "Public Domain"
        case .rejected:     return "Unknown"
        }
    }

    private func sourceName(_ s: String) -> String {
        switch s {
        case "internet_archive": return "Internet Archive"
        case "fma":              return "Free Music Archive"
        case "oxford_lectures":  return "Oxford University"
        case "podcast":          return "Podcast"
        case "nps":              return "National Park Service"
        case "freesound":        return "Freesound"
        case "local":            return "My Files"
        default:                  return s
        }
    }

    // Prefer the live AVPlayer duration (accurate for IA tracks fetched with
    // duration 0); fall back to the stored per-file duration.
    private func trackInfoDuration(_ track: Track) -> Double? {
        if let d = playerVM.trackDuration, d > 0 { return d }
        return track.duration > 0 ? track.duration : nil
    }

    // "Book" for Audiobooks-category channels or LibriVox/audiobook items;
    // "Album" otherwise.
    // Keep long book/album titles from blowing out the menu label.
    private func shortName(_ s: String, max: Int = 26) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }

    private func itemKindLabel(_ track: Track) -> String {
        if playerVM.currentChannel?.category == "Audiobooks" { return "Book" }
        let hay = (track.parentIdentifier ?? track.id).lowercased()
        if hay.contains("librivox") || track.tags.contains(where: {
            $0.contains("librivox") || $0.contains("audiobook")
        }) { return "Book" }
        return "Album"
    }

    // Everything else, surfaced behind the "Full Metadata" disclosure so the
    // summary stays scannable. Empty/placeholder values are omitted.
    private func fullMetadata(_ track: Track) -> [(String, String)] {
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !v.isEmpty, v.lowercased() != "unknown" else { return }
            rows.append((label, v))
        }
        add("License", licenseName(track.license))
        add("Source", sourceName(track.source))
        add("Identifier", track.id)
        if let part = track.partNumber, let total = track.totalParts, total > 1 {
            add("Part", "\(part) of \(total)")
        }
        add("Item", track.parentIdentifier)
        if let multi = track.isMultiPart {
            add("Multi-part item", multi ? "Yes" : "No")
        }
        if !track.tags.isEmpty { add("Tags", track.tags.joined(separator: ", ")) }
        if !track.instruments.isEmpty {
            add("Instruments", track.instruments.joined(separator: ", "))
        }
        if track.rawCreator != track.artist { add("Raw creator", track.rawCreator) }
        if let added = track.addedDate {
            add("Added", added.formatted(.dateTime.year().month().day()))
        }
        if let rec = track.recordingDate {
            add("Recorded", rec.formatted(.dateTime.year().month().day()))
        }
        add("Quality score", String(format: "%.2f", track.qualityScore))
        add("Metadata confidence", String(format: "%.2f", track.metadataConfidence))
        add("Stream URL", track.streamURL.absoluteString)
        add("Local file", track.localFilePath)
        return rows
    }

    // MARK: - Layout geometry
    //
    // Helper functions (not @ViewBuilder `let` bindings, which can interact
    // badly with SwiftUI's layout engine) shared by the screen panel and the
    // wheel so they read as one physical device.

    // Click-wheel diameter. Floor at 80 pt prevents a negative/invisible frame
    // when GeometryReader briefly reports zero during sheet-dismiss animations.
    private func wheelDiameter(_ geo: GeometryProxy) -> CGFloat {
        max(80.0, min(geo.size.width - 48, geo.size.height * 0.50 - 32))
    }

    // The wheel is centered, so its gap to each screen edge is exactly this.
    // The screen panel uses the same value for its left/right AND top margins
    // so panel and wheel have identical insets from the screen edge.
    private func deviceMargin(_ geo: GeometryProxy) -> CGFloat {
        max(12.0, (geo.size.width - wheelDiameter(geo)) / 2)
    }

    // MARK: - Helpers

    // Treats empty / "Unknown" (case-insensitive) placeholder values as
    // absent so the UI shows nothing rather than the word "Unknown".
    private func cleaned(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !v.isEmpty, v.lowercased() != "unknown" else { return nil }
        return v
    }

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
    // Seek-wheel inputs (duration == 0 ⇒ pure transport, no seeking/arc).
    var currentTime: Double = 0
    var duration: Double = 0
    // Ambient-loop channels: no back/forward and no seeking, but play/pause
    // stays so the loop can be paused. transportEnabled gates back/forward
    // (+ seek); playPauseEnabled gates the bottom play/pause; MENU is always on.
    var transportEnabled: Bool = true
    var playPauseEnabled: Bool = true
    var onSeek: (Double) -> Void = { _ in }
    var onScrubChanged: (Bool) -> Void = { _ in }
    let onMenu:      () -> Void
    let onBack:      () -> Void
    let onForward:   () -> Void
    let onPlayPause: () -> Void

    @State private var tapTrigger = 0
    @State private var isDragging = false
    @StateObject private var seekVM = SeekWheelViewModel()

    var body: some View {
        GeometryReader { geo in
            let size    = min(geo.size.width, geo.size.height)
            let outerR  = size / 2
            let innerR  = size * 0.225
            let midRing = (outerR + innerR) / 2
            let arcR    = (outerR + midRing) / 2
            let fraction = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
            let thumbA  = angle(for: currentTime, duration: duration)

            ZStack {
                // Outer ring — flat metallic
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

                // Progress arc + thumb (only when the track has a duration).
                if duration > 0 {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.accentColor,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: arcR * 2, height: arcR * 2)
                        .allowsHitTesting(false)

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 16, height: 16)
                        .shadow(radius: 3)
                        .offset(x: arcR * cos(thumbA), y: arcR * sin(thumbA))
                        .allowsHitTesting(false)
                }

                // Center button
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: innerR * 2, height: innerR * 2)
                    .allowsHitTesting(false)

                // MENU icon (top)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .offset(y: -midRing)
                    .allowsHitTesting(false)

                if transportEnabled {
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
                }

                if playPauseEnabled {
                    // Play/Pause (bottom)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)
                        .offset(y: midRing)
                        .allowsHitTesting(false)
                }
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
                            if dy < 0 { onMenu() }
                            else if playPauseEnabled { onPlayPause() }
                        } else if transportEnabled {
                            if dx < 0 { onBack() } else { onForward() }
                        }
                    }
            )
            // Drag-to-seek. minimumDistance:12 so quick taps still hit the
            // transport SpatialTapGesture; .simultaneousGesture so it doesn't
            // block parent gestures. Only active when the track has duration.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        if !isDragging {
                            isDragging = true
                            seekVM.duration = duration
                            seekVM.currentTime = currentTime
                            seekVM.onSeek = onSeek
                            onScrubChanged(true)
                        } else {
                            seekVM.duration = duration
                        }
                        seekVM.handleDrag(
                            location: value.location,
                            center: CGPoint(x: size / 2, y: size / 2)
                        )
                    }
                    .onEnded { _ in
                        guard isDragging else { return }
                        seekVM.handleDragEnded()
                        onScrubChanged(false)
                        isDragging = false
                    }
            )
            .onAppear { seekVM.onAppear() }
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
