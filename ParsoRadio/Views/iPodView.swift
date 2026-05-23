import SwiftUI

struct iPodView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showChapters = false
    @State private var sleepTimerNow: Date = Date()
    private static let sleepTimerOptions: [Int] = [15, 30, 45, 60]
    @State private var pendingChannel: Channel = {
        let raw = UserDefaults.standard.string(forKey: "lastChannelId") ?? "spanish-guitar"
        let lastId = PlayerViewModel.migratedChannelId(raw) ?? raw
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
    @State private var isCurrentTrackFavorite = false
    @State private var showWheelHelp = false
    @AppStorage("didShowWheelHelp") private var didShowWheelHelp = false
    // Wheel MENU opens the Main Menu sheet, optionally pre-navigated to the
    // current playlist or channel-info (single tap); double tap = root menu.
    @State private var menuRoute: MenuRoute? = nil
    // Non-nil while the user is dragging the progress bar (overrides the
    // player position so the bar follows the finger).
    @State private var scrubFraction: Double? = nil

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

    // The same SF Symbol the main menu/channel-selector list uses for this
    // source, so the top-left label of the track box is unambiguous.
    private var titleIcon: String? {
        if let pl = playerVM.currentPlaylist {
            return pl.isFavorites ? "heart.fill" : "music.note.list"
        }
        return playerVM.currentChannel?.icon
    }

    private var titleText: String {
        playerVM.currentPlaylist?.name ?? playerVM.currentChannel?.name ?? ""
    }

    // Two sizes only on the main page: one larger bold for the playlist/
    // channel name and track title; one smaller regular for artist, part,
    // date and time labels. @ScaledMetric so they honor Dynamic Type (the
    // .dynamicTypeSize clamp on the panel keeps the layout coherent at the
    // extreme settings).
    @ScaledMetric(relativeTo: .title3)      private var mainBoldSize: CGFloat = 19
    @ScaledMetric(relativeTo: .subheadline) private var mainRegularSize: CGFloat = 14
    // Brand dark blue (matches the wheel's old progress arc) — used for the
    // elapsed-progress fill on the dark scrim.
    private static let progressBlue = Color(red: 0.18, green: 0.42, blue: 0.95)
    // Device-body color adapts to appearance (HIG): a deep slate in Dark Mode,
    // a lighter slate in Light Mode.
    private static let deviceBody = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.150, green: 0.170, blue: 0.215, alpha: 1)
            : UIColor(red: 0.290, green: 0.333, blue: 0.408, alpha: 1)
    })

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Device body — adapts to Light/Dark appearance.
                Self.deviceBody
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
                        duration: isAmbientLoop ? 0 : (playerVM.trackDuration ?? 0),
                        transportEnabled: !isAmbientLoop,
                        onSeek: { playerVM.seek(to: $0) },
                        onSeekBy: { playerVM.seekBy($0) },
                        onScrubChanged: { playerVM.setScrubbing($0) },
                        onMenu:        { openMenu(contextual: true) },
                        onMenuRoot:    { openMenu(contextual: false) },
                        onPrevTrack:   { Task { await playerVM.goToPreviousTrack() } },
                        onNextTrack:   { playerVM.skip() },
                        onPlayPause:   { playerVM.togglePlayPause() },
                        onCenter:      { if playerVM.currentTrack != nil { showMoreOptions = true } }
                    )
                    .frame(width: wheelDiameter(geo), height: wheelDiameter(geo))

                    Spacer(minLength: deviceMargin(geo))
                }
                // On iPad (regular width) cap the "device" to a phone-like
                // width and centre it, so the wheel/track box stay iPod-
                // proportioned instead of stretching across a 12.9" display.
                .frame(maxWidth: contentWidth(geo), maxHeight: .infinity)
                .frame(maxWidth: .infinity)
                // Match the device-body Color: extend to the physical screen
                // bottom so the bottom spacer (and thus the wheel centering)
                // is measured to the real screen edge, not the safe-area inset
                // — otherwise the wheel looks bottom-heavy.
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .sheet(isPresented: $showMainMenu) {
            MainMenuView(
                initialRoute: menuRoute,
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
        .sheet(isPresented: $showWheelHelp) {
            WheelHelpView()
        }
        // A drag-to-seek gesture interrupted by a sheet presentation can leave
        // isScrubbing stuck true, which freezes the progress bar / elapsed time
        // until the next track. Clear it whenever a sheet closes.
        .onChange(of: showMoreOptions) { _, shown in
            if !shown { playerVM.isScrubbing = false }
        }
        .onChange(of: showMainMenu) { _, shown in
            if !shown { playerVM.isScrubbing = false }
        }
        .task {
            await playlistVM.loadPlaylists()
            let wasPlaying = UserDefaults.standard.bool(forKey: "wasPlayingOnQuit")
            UserDefaults.standard.removeObject(forKey: "wasPlayingOnQuit")
            // Resume EXACTLY where the user was — same channel/playlist, track
            // and offset — including after an app update.
            await playerVM.restoreLastSession(fallbackChannel: pendingChannel,
                                              autoPlay: wasPlaying)
            // First launch: show the wheel guide once so the gestures are
            // discoverable.
            if !didShowWheelHelp {
                didShowWheelHelp = true
                showWheelHelp = true
            }
        }
    }

    // MARK: - Screen Panel

    private var screenPanel: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed album art background
            artworkBackground

            // Top scrim — keeps the channel title readable over light artwork.
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .center
            )

            // Bottom scrim for the track metadata / scrubber legibility.
            // Slightly stronger so white text clears the 4.5:1 contrast bar
            // even over a bright album cover.
            LinearGradient(
                colors: [.clear, .black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                // Playlist or channel name only. NO stale fallback to the
                // last-selected channel: a search-result/standalone play has
                // neither, so the label stays blank until real content shows.
                HStack(spacing: 8) {
                    if let icon = titleIcon {
                        Image(systemName: icon)
                            .font(.system(size: mainBoldSize,
                                           weight: .semibold))
                    }
                    Text(titleText)
                        .font(.system(size: mainBoldSize,
                                       weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                // Label only — navigation moved to the wheel MENU button.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Now playing from \(titleText.isEmpty ? "nothing" : titleText)")
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
        // Status indicators (top-right): shuffle (blue when active) and
        // repeat-one. Both are display-only; toggled from Track Info.
        .overlay(alignment: .topTrailing) {
            if !isAmbientLoop, playerVM.currentTrack != nil {
                HStack(spacing: 8) {
                    if playerVM.shuffleMode {
                        statusBadge("shuffle", tint: .blue, label: "Shuffle is on")
                    }
                    if playerVM.repeatMode == .one {
                        statusBadge("repeat.1", tint: .white, label: "Repeat track is on")
                    }
                }
                .padding(12)
            }
        }
        // Unmistakable loading indicator centred on the screen while a track
        // is resolving/buffering (the small inline spinner was easy to miss).
        .overlay { if playerVM.isLoading { loadingOverlay } }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        // Dynamic Type clamp — respect the user's text-size setting but keep
        // the track box layout coherent at the extreme sizes.
        .dynamicTypeSize(.medium ... .accessibility2)
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
                            playerVM.currentChannel?.id == "ambient-rain" ? 1.0 : 0.5,
                        isPlaying: playerVM.isPlaying)
                } else if let art = playerVM.currentArtwork {
                    Image(uiImage: art)
                        .resizable()
                        .scaledToFill()
                } else {
                    // No artwork → per-track procedural visualizer (seeded by
                    // the track so it always changes; never a stale image).
                    ProceduralVisualizerView(
                        seed: playerVM.currentTrack?.id ?? displayChannel.id,
                        isPlaying: playerVM.isPlaying)
                }
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8),
                       value: playerVM.currentTrack?.id)
            // Purely decorative (album art / ambient video / visualizer).
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func trackMetadataStack(track: Track) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            if playerVM.isLoading, let msg = playerVM.loadingMessage {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.8).tint(.white)
                    Text(msg)
                        .font(.system(size: mainRegularSize))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Text(track.title)
                .font(.system(size: mainBoldSize, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let artist = cleaned(track.artist) {
                Text(artist)
                    .font(.system(size: mainRegularSize))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            if let part = track.partNumber, let total = track.totalParts, total > 1 {
                Text("Part \(part) of \(total)")
                    .font(.system(size: mainRegularSize))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // News episodes: show the publish date on the now-playing line
            // (this single-track screen IS the news "listing").
            if playerVM.currentChannel?.preferredSource == "podcast",
               let date = track.bestDate {
                Text(date.formatted(.dateTime.year().month().day()))
                    .font(.system(size: mainRegularSize))
                    .foregroundStyle(.white.opacity(0.7))
            }
            // License/source intentionally NOT shown here — only in the
            // Track Info popup — to keep the main track box uncluttered.
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        // One spoken element: "Title, Artist, Part 2 of 5" rather than four
        // separate VoiceOver stops.
        .accessibilityElement(children: .combine)
    }

    private func statusBadge(_ systemName: String, tint: Color, label: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: mainRegularSize, weight: .semibold))
            .foregroundStyle(tint)
            .padding(8)
            .background(.black.opacity(0.35), in: Circle())
            .accessibilityLabel(label)
    }

    // Centered, high-visibility loading state shown over the whole track box.
    private var loadingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text(playerVM.loadingMessage ?? "Loading…")
                .font(.system(size: mainRegularSize, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(22)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.15))
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(playerVM.loadingMessage ?? "Loading")
    }

    @ViewBuilder
    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white)
            Text(playerVM.loadingMessage ?? "Loading…")
                .font(.system(size: mainRegularSize))
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
                .font(.system(size: mainRegularSize))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.trailing)
            Button("Try Again") {
                if let ch = playerVM.currentChannel {
                    Task { await playerVM.load(channel: ch) }
                }
            }
            .font(.system(size: mainRegularSize))
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
            .font(.system(size: mainRegularSize))
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }

    // The track box now carries ONLY the position display: elapsed / remaining
    // times + a draggable progress bar. Favorites, the ••• info button and the
    // tap zones were removed — transport + track-info live on the wheel
    // (wheel centre = Track Info; ±10 / track-skip / scrub on the sides).
    @ViewBuilder
    private var scrubberRow: some View {
        if isAmbientLoop {
            EmptyView()                       // a forever loop has nothing to scrub
        } else if let dur = playerVM.trackDuration, dur > 0 {
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text(formatTime(playerVM.currentPosition))
                        .font(.system(size: mainRegularSize))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                        .accessibilityHidden(true)
                    Spacer()
                    Text("-" + formatTime(max(0, dur - playerVM.currentPosition)))
                        .font(.system(size: mainRegularSize))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                progressBar(duration: dur)
                    .padding(.horizontal, 14)
            }
            .padding(.vertical, 2)
        }
    }

    // Draggable elapsed-progress bar (common music-UI placement: bottom of
    // the track box). Tap or drag anywhere to seek. Dark-blue fill matches
    // the wheel's old progress arc and is distinct from the smaller controls
    // above so the user knows where the scrubbing surface starts.
    private func progressBar(duration: Double) -> some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let frac = scrubFraction
                ?? min(max(playerVM.currentPosition / duration, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: 5)
                Capsule().fill(Self.progressBlue)
                    .frame(width: w * CGFloat(frac), height: 5)
                Circle().fill(.white)
                    .overlay(Circle().stroke(Self.progressBlue, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: min(max(w * CGFloat(frac), 0), w) - 7)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        playerVM.setScrubbing(true)
                        let f = min(max(Double(v.location.x / w), 0), 1)
                        scrubFraction = f
                        playerVM.currentPosition = f * duration
                    }
                    .onEnded { v in
                        let f = min(max(Double(v.location.x / w), 0), 1)
                        playerVM.seek(to: f * duration)
                        scrubFraction = nil
                        playerVM.setScrubbing(false)
                    }
            )
        }
        .frame(height: 16)
        // VoiceOver: a real adjustable "slider" — swipe up/down seeks ±15 s.
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            "\(formatTime(playerVM.currentPosition)) of \(formatTime(duration)), \(formatTime(max(0, duration - playerVM.currentPosition))) remaining")
        .accessibilityHint("Swipe up or down to seek by 15 seconds")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                playerVM.seek(to: min(duration, playerVM.currentPosition + 15))
            case .decrement:
                playerVM.seek(to: max(0, playerVM.currentPosition - 15))
            @unknown default:
                break
            }
        }
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

                    // Playback controls / output (skip for ambient loops —
                    // a single forever-looping track has nothing to speed up).
                    if !isAmbientLoop {
                        Section("Playback") {
                            playbackSpeedRow
                            sleepTimerRow
                            Toggle(isOn: Binding(
                                get: { playerVM.shuffleMode },
                                set: { on in
                                    if playerVM.shuffleMode != on { playerVM.toggleShuffle() }
                                }
                            )) {
                                Label("Shuffle", systemImage: "shuffle")
                            }
                            .accessibilityHint("When on, a blue shuffle icon shows on the player and tracks play in random order. Resets when you change channels.")
                            Toggle(isOn: Binding(
                                get: { playerVM.repeatMode == .one },
                                set: { on in
                                    if (playerVM.repeatMode == .one) != on { playerVM.toggleRepeat() }
                                }
                            )) {
                                Label("Repeat Track", systemImage: "repeat.1")
                            }
                            .accessibilityHint("When on, a repeat icon shows on the player and the track loops")
                            if playerVM.currentTrackIsMultiPart {
                                NavigationLink {
                                    ChapterListView(onDismiss: { showMoreOptions = false })
                                        .environmentObject(playerVM)
                                } label: {
                                    Label(usesChapterTerminology ? "Chapter List" : "Track List",
                                          systemImage: "list.number")
                                }
                            }
                            HStack {
                                Label("AirPlay", systemImage: "airplayaudio")
                                Spacer()
                                AirPlayButton()
                                    .frame(width: 32, height: 32)
                                    .accessibilityLabel("AirPlay")
                            }
                        }

                        bookmarksSection(for: track)

                        Section {
                            if let shareURL = shareURL(for: track) {
                                ShareLink(item: shareURL,
                                          message: Text(track.title)) {
                                    Label("Share Track", systemImage: "square.and.arrow.up")
                                }
                            }
                            Button {
                                Task {
                                    await playlistVM.toggleFavorite(track)
                                    isCurrentTrackFavorite = await playlistVM.isInFavorites(track)
                                }
                            } label: {
                                Label(isCurrentTrackFavorite ? "Remove from Favorites" : "Add to Favorites",
                                      systemImage: isCurrentTrackFavorite ? "heart.fill" : "heart")
                                    .foregroundStyle(isCurrentTrackFavorite ? Color.red : Color.accentColor)
                            }
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
            .navigationTitle(usesChapterTerminology ? "Chapter Info" : "Track Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showMoreOptions = false }
                }
            }
            .task(id: playerVM.currentTrack?.id) {
                if let t = playerVM.currentTrack {
                    isCurrentTrackFavorite = await playlistVM.isInFavorites(t)
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
        .accessibilityElement(children: .combine)
    }

    // MARK: - More Options helper rows

    private var playbackSpeedRow: some View {
        Picker(selection: Binding(
            get: { playerVM.playbackRate },
            set: { playerVM.setPlaybackRate($0) }
        )) {
            ForEach(PlayerViewModel.playbackRateOptions, id: \.self) { r in
                Text(rateLabel(r)).tag(r)
            }
        } label: {
            Label("Speed", systemImage: "speedometer")
        }
        .pickerStyle(.menu)
        .accessibilityHint("Sets the playback speed from half normal to double speed")
    }

    private func rateLabel(_ r: Double) -> String {
        // 1× displays as "1×" not "1.0×".
        if r.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(r))×"
        }
        return String(format: "%g×", r)
    }

    @ViewBuilder
    private var sleepTimerRow: some View {
        let active = playerVM.isSleepTimerActive
        Menu {
            ForEach(Self.sleepTimerOptions, id: \.self) { mins in
                Button("\(mins) minutes") { playerVM.startSleepTimer(minutes: mins) }
            }
            Button("End of Track") { playerVM.setSleepAtEndOfTrack(true) }
            if active {
                Divider()
                Button(role: .destructive) {
                    playerVM.cancelSleepTimer()
                } label: { Text("Cancel Sleep Timer") }
            }
        } label: {
            HStack {
                Label("Sleep Timer", systemImage: active ? "moon.fill" : "moon")
                Spacer()
                Text(sleepTimerStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        // Tick the local clock once a second while a timer is active so the
        // countdown label refreshes without a publisher.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            sleepTimerNow = now
        }
        .accessibilityLabel("Sleep timer, currently \(sleepTimerStatus)")
        .accessibilityHint("Choose a duration or end-of-track to pause playback automatically")
    }

    private var sleepTimerStatus: String {
        if playerVM.sleepAtEndOfTrack { return "End of Track" }
        if let ends = playerVM.sleepTimerEndsAt {
            let remaining = max(0, ends.timeIntervalSince(sleepTimerNow))
            return formatTime(remaining)
        }
        return "Off"
    }

    @ViewBuilder
    private func bookmarksSection(for track: Track) -> some View {
        Section("Bookmarks") {
            Button {
                Task { await playerVM.addBookmarkAtCurrentPosition() }
            } label: {
                Label("Bookmark This Spot (\(formatTime(playerVM.currentPosition)))",
                      systemImage: "bookmark")
            }
            .disabled(track.id != playerVM.currentTrack?.id)

            if playerVM.bookmarksForCurrentTrack.isEmpty {
                Text("No bookmarks for this track yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(playerVM.bookmarksForCurrentTrack) { bm in
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bm.label ?? formatTime(bm.positionSeconds))
                                .font(.body)
                            if bm.label != nil {
                                Text(formatTime(bm.positionSeconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { playerVM.seekToBookmark(bm) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await playerVM.deleteBookmark(bm) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Seeks to this bookmark")
                }
            }
        }
    }

    /// Public-facing URL for the share sheet. Logic lives in
    /// `ShareURLBuilder` so it's directly unit-testable.
    private func shareURL(for track: Track) -> URL? {
        ShareURLBuilder.url(for: track)
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

    // Books, book channels, lecture channels, and playlists built from books
    // use "Chapter" terminology; everything else uses "Track".
    private var usesChapterTerminology: Bool {
        if playerVM.currentChannel?.category == "Lectures" { return true }
        guard let t = playerVM.currentTrack else { return false }
        return itemKindLabel(t) == "Book"
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

    // Effective layout width — capped on iPad (regular width) so the "device"
    // stays phone-sized and centered rather than filling the whole screen.
    private func contentWidth(_ geo: GeometryProxy) -> CGFloat {
        horizontalSizeClass == .regular ? min(geo.size.width, 480) : geo.size.width
    }

    // Click-wheel diameter. Floor at 80 pt prevents a negative/invisible frame
    // when GeometryReader briefly reports zero during sheet-dismiss animations.
    private func wheelDiameter(_ geo: GeometryProxy) -> CGFloat {
        max(80.0, min(contentWidth(geo) - 48, geo.size.height * 0.50 - 32))
    }

    // The wheel is centered, so its gap to each screen edge is exactly this.
    // The screen panel uses the same value for its left/right AND top margins
    // so panel and wheel have identical insets from the screen edge.
    private func deviceMargin(_ geo: GeometryProxy) -> CGFloat {
        max(12.0, (contentWidth(geo) - wheelDiameter(geo)) / 2)
    }

    // MARK: - Helpers

    // Wheel MENU: single tap (contextual) opens the Main Menu pre-navigated to
    // the current playlist / channel-info; double tap (contextual:false) opens
    // the Main Menu root. The back chevron on those pushed screens returns to
    // the menu list.
    private func openMenu(contextual: Bool) {
        // Leaving the player screen → save the EXACT current spot so the
        // playlist/channel resume marker reflects where the user actually is.
        playerVM.saveCurrentSpot()
        if contextual, let pl = playerVM.currentPlaylist {
            menuRoute = .playlist(pl)
        } else if contextual, let ch = playerVM.currentChannel {
            menuRoute = .channelInfo(ch)
        } else {
            menuRoute = nil
        }
        showMainMenu = true
    }

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

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

}

// MARK: - Click Wheel

struct ClickWheel: View {
    // Single source of truth for icon point size on the main screen.
    static let iconSize: CGFloat = 22

    // Wheel colors are dedicated (not system grouped-background grays) so the
    // wheel clearly stands out from the dark device body in low light. The ring
    // is a light silver in BOTH appearances — the iconic iPod look — kept a
    // touch muted in dark so it isn't glary; the centre well is darker so the
    // ring still reads as a ring; glyphs are a fixed near-black that contrasts
    // on the light ring in both modes.
    static let ring = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.60, green: 0.62, blue: 0.68, alpha: 1)
            : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    })
    static let well = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.42, blue: 0.48, alpha: 1)
            : UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1)
    })
    static let ringEdge = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(white: 0.78, alpha: 0.5)
            : UIColor(white: 0.0, alpha: 0.18)
    })
    static let glyph = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
            : UIColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1)
    })

    let isPlaying: Bool
    var currentTime: Double = 0
    var duration: Double = 0
    // Ambient-loop channels: no back/forward and no seeking, but play/pause
    // stays so the loop can be paused.
    var transportEnabled: Bool = true
    var playPauseEnabled: Bool = true
    var onSeek: (Double) -> Void = { _ in }       // absolute (hold-scrub)
    var onSeekBy: (Double) -> Void = { _ in }     // relative ±10 (single tap)
    var onScrubChanged: (Bool) -> Void = { _ in }
    let onMenu:      () -> Void                    // single tap → context dest
    var onMenuRoot:  () -> Void = {}               // double tap → Main Menu
    let onPrevTrack: () -> Void                    // double-tap back
    let onNextTrack: () -> Void                    // double-tap forward
    let onPlayPause: () -> Void
    let onCenter:    () -> Void                    // centre tap → Track Info

    @State private var tapTrigger = 0
    @State private var isDragging = false
    @StateObject private var seekVM = SeekWheelViewModel()

    var body: some View {
        GeometryReader { geo in
            let size    = min(geo.size.width, geo.size.height)
            let innerR  = size * 0.225
            let outerR  = size / 2
            let midRing = (outerR + innerR) / 2

            ZStack {
                // Outer ring — dedicated high-contrast color + a thin edge so it
                // separates from the device body even in low light.
                Circle()
                    .fill(ClickWheel.ring)
                    .overlay(Circle().strokeBorder(ClickWheel.ringEdge, lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 7, y: 3)
                // Centre well (now opens Track Info — no repeat glyph).
                Circle()
                    .fill(ClickWheel.well)
                    .frame(width: innerR * 2, height: innerR * 2)
                    .allowsHitTesting(false)

                // MENU (top)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: ClickWheel.iconSize, weight: .medium))
                    .foregroundStyle(ClickWheel.glyph)
                    .offset(y: -midRing).allowsHitTesting(false)
                if transportEnabled {
                    Image(systemName: "backward.fill")
                        .font(.system(size: ClickWheel.iconSize, weight: .medium))
                        .foregroundStyle(ClickWheel.glyph)
                        .offset(x: -midRing).allowsHitTesting(false)
                    Image(systemName: "forward.fill")
                        .font(.system(size: ClickWheel.iconSize, weight: .medium))
                        .foregroundStyle(ClickWheel.glyph)
                        .offset(x: midRing).allowsHitTesting(false)
                }
                if playPauseEnabled {
                    // Fixed combined glyph — never swaps between play and pause.
                    Image(systemName: "playpause.fill")
                        .font(.system(size: ClickWheel.iconSize, weight: .medium))
                        .foregroundStyle(ClickWheel.glyph)
                        .offset(y: midRing).allowsHitTesting(false)
                }

                // Hit grid: 3×3 of equal cells over the wheel. Centre column
                // top=MENU, centre=Track Info, bottom=Play/Pause; left/right
                // columns are the back/forward regions (tap=±10s, double=skip).
                hitGrid(cell: size / 3)
            }
            .frame(width: size, height: size)
            // Rotational drag-to-scrub on the ring (classic click-wheel feel):
            // spin a finger around the wheel to move the elapsed timer
            // forward/back. Runs simultaneously with the per-region tap
            // gestures; WheelSideRegion skips its tap when the touch moved, so
            // a scrub never also fires a ±10 tap. Only the ring scrubs — touches
            // starting in the centre well are ignored here.
            .simultaneousGesture(
                DragGesture(minimumDistance: 14, coordinateSpace: .local)
                    .onChanged { value in
                        guard duration > 0, transportEnabled else { return }
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let startR = hypot(value.startLocation.x - center.x,
                                           value.startLocation.y - center.y)
                        guard startR > innerR else { return }   // not the centre well
                        if !isDragging {
                            isDragging = true
                            seekVM.currentTime = currentTime
                            seekVM.onSeek = onSeek
                        }
                        seekVM.duration = duration
                        // Stamp scrub activity on EVERY move so the self-healing
                        // guard knows the drag is still live.
                        onScrubChanged(true)
                        seekVM.handleDrag(location: value.location, center: center)
                    }
                    .onEnded { _ in
                        guard isDragging else { return }
                        seekVM.handleDragEnded()
                        onScrubChanged(false)
                        isDragging = false
                    }
            )
            .onAppear { seekVM.onAppear() }
            .sensoryFeedback(.impact(weight: .light), trigger: tapTrigger)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback controls")
            .accessibilityValue(isPlaying ? "Playing" : "Paused")
            .accessibilityHint(duration > 0
                ? "Swipe up or down to seek by 15 seconds. Use the rotor for menu, track skip and track info."
                : "Use the rotor for menu and play or pause.")
            .accessibilityAction(.default) { onPlayPause() }
            .accessibilityActions {
                Button(isPlaying ? "Pause" : "Play") { onPlayPause() }
                Button("Open") { onMenu() }
                Button("Main Menu") { onMenuRoot() }
                Button("Track Info") { onCenter() }
                if transportEnabled {
                    Button("Next Track") { onNextTrack() }
                    Button("Previous Track") { onPrevTrack() }
                }
            }
            .accessibilityAdjustableAction { direction in
                guard duration > 0 else { return }
                switch direction {
                case .increment: onSeekBy(15)
                case .decrement: onSeekBy(-15)
                @unknown default: break
                }
            }
        }
    }

    @ViewBuilder
    private func hitGrid(cell: CGFloat) -> some View {
        let tap = { tapTrigger += 1 }
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: cell, height: cell)            // corner
                WheelMenuRegion(onSingle: onMenu, onDouble: onMenuRoot, haptic: tap)
                    .frame(width: cell, height: cell)                    // MENU
                Color.clear.frame(width: cell, height: cell)            // corner
            }
            HStack(spacing: 0) {
                WheelSideRegion(direction: -1, enabled: transportEnabled,
                                onSeekBy: onSeekBy,
                                onTrackSkip: onPrevTrack, haptic: tap)
                    .frame(width: cell, height: cell)
                tapCell { onCenter() }                                   // Track Info
                WheelSideRegion(direction: 1, enabled: transportEnabled,
                                onSeekBy: onSeekBy,
                                onTrackSkip: onNextTrack, haptic: tap)
                    .frame(width: cell, height: cell)
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: cell, height: cell)            // corner
                tapCell { if playPauseEnabled { onPlayPause() } }        // Play/Pause
                Color.clear.frame(width: cell, height: cell)            // corner
            }
        }
    }

    private func tapCell(_ action: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { tapTrigger += 1; action() }
    }
}

// One back/forward wheel region: single tap = seek ±10 s, double tap = skip
// track. Continuous scrub is handled at the wheel level by rotational
// drag-to-scrub, so a touch that MOVED is treated as a scrub here and never
// fires a tap.
private struct WheelSideRegion: View {
    let direction: Int          // -1 back, +1 forward
    let enabled: Bool
    let onSeekBy: (Double) -> Void
    let onTrackSkip: () -> Void
    let haptic: () -> Void

    @State private var lastTapDate: Date? = nil
    @State private var pendingSingleTap: DispatchWorkItem? = nil
    @State private var maxMove: CGFloat = 0

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let m = hypot(v.translation.width, v.translation.height)
                        if m > maxMove { maxMove = m }
                    }
                    .onEnded { _ in
                        let moved = maxMove
                        maxMove = 0
                        guard enabled else { return }
                        // A moved touch is a rotational scrub (handled at the
                        // wheel level) — never a ±10 / track-skip tap.
                        if moved > 14 { return }
                        registerTap()
                    }
            )
    }

    private func registerTap() {
        haptic()
        if let last = lastTapDate, Date().timeIntervalSince(last) < 0.3 {
            // Double tap → skip a whole track.
            pendingSingleTap?.cancel(); pendingSingleTap = nil
            lastTapDate = nil
            onTrackSkip()
        } else {
            // Defer the single-tap ±10 s seek by the double-tap window.
            lastTapDate = Date()
            let work = DispatchWorkItem {
                onSeekBy(Double(direction) * 10)
                lastTapDate = nil
            }
            pendingSingleTap = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: work)
        }
    }
}

// The wheel MENU region: single tap → contextual destination (playlist /
// channel info), double tap → straight to the Main Menu.
private struct WheelMenuRegion: View {
    let onSingle: () -> Void
    let onDouble: () -> Void
    let haptic: () -> Void
    @State private var lastTap: Date? = nil
    @State private var pending: DispatchWorkItem? = nil

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                haptic()
                if let last = lastTap, Date().timeIntervalSince(last) < 0.3 {
                    pending?.cancel(); pending = nil; lastTap = nil
                    onDouble()
                } else {
                    lastTap = Date()
                    let work = DispatchWorkItem { onSingle(); lastTap = nil }
                    pending = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: work)
                }
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
