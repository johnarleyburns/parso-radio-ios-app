import SwiftUI

struct iPodView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showChapters = false
    @State private var sleepTimerNow: Date = Date()
    private static let sleepTimerOptions: [Int] = [15, 30, 45, 60]
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

    // Two sizes only on the main page (per spec): one larger bold for the
    // playlist/channel name and track title; one smaller regular for artist,
    // part, date and time labels.
    private static let mainBoldSize: CGFloat = 19
    private static let mainRegularSize: CGFloat = 14
    // Brand dark blue (matches the wheel's old progress arc) — used for the
    // elapsed-progress fill on the dark scrim.
    private static let progressBlue = Color(red: 0.18, green: 0.42, blue: 0.95)

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
                        duration: isAmbientLoop ? 0 : (playerVM.trackDuration ?? 0),
                        transportEnabled: !isAmbientLoop,
                        // Repeat-One phantom toggle: real tracks only, never
                        // ambient loops (which already repeat).
                        repeatEnabled: !isAmbientLoop && playerVM.currentTrack != nil,
                        repeatOn: playerVM.repeatMode == .one,
                        onRepeatToggle: { playerVM.toggleRepeat() },
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
                HStack(spacing: 8) {
                    if let icon = titleIcon {
                        Image(systemName: icon)
                            .font(.system(size: Self.mainBoldSize,
                                           weight: .semibold))
                    }
                    Text(titleText)
                        .font(.system(size: Self.mainBoldSize,
                                       weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.95))
                .contentShape(Rectangle())
                // Tapping the playlist/channel name opens the menu
                // (not track info — that's the rest of the panel / •••).
                .onTapGesture { showMainMenu = true }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(
                    "Now playing from \(titleText.isEmpty ? "nothing" : titleText)")
                .accessibilityHint("Opens the menu to pick a channel or playlist")
                .accessibilityAction { showMainMenu = true }
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
        .overlay { centerTapZones }
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

    // Central band of the track box → tap zones: left third seek −10 s,
    // right third seek +10 s, centre third play/pause. Sized to the middle
    // ~50% so it never covers the top-left title (→ menu) or the bottom
    // controls/progress bar, which keep their own gestures.
    private var centerTapZones: some View {
        GeometryReader { g in
            let w = max(g.size.width, 1)
            let h = g.size.height
            Color.clear
                .contentShape(Rectangle())
                .frame(width: w, height: max(0, h * 0.50))
                .position(x: w / 2, y: h * 0.52)
                .gesture(
                    SpatialTapGesture().onEnded { v in
                        guard playerVM.currentTrack != nil else { return }
                        let x = v.location.x
                        if x < w / 3 {
                            if playerVM.trackDuration != nil {
                                playerVM.seek(to: max(0, playerVM.currentPosition - 10))
                            }
                        } else if x > 2 * w / 3 {
                            if let d = playerVM.trackDuration {
                                playerVM.seek(to: min(d, playerVM.currentPosition + 10))
                            }
                        } else {
                            playerVM.togglePlayPause()
                        }
                    }
                )
        }
        // Sighted-only convenience layer; every action it offers is also a
        // VoiceOver custom action on the wheel + the adjustable progress bar.
        .accessibilityHidden(true)
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
                        .font(.system(size: Self.mainRegularSize))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Text(track.title)
                .font(.system(size: Self.mainBoldSize, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let artist = cleaned(track.artist) {
                Text(artist)
                    .font(.system(size: Self.mainRegularSize))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            if let part = track.partNumber, let total = track.totalParts, total > 1 {
                Text("Part \(part) of \(total)")
                    .font(.system(size: Self.mainRegularSize))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // News episodes: show the publish date on the now-playing line
            // (this single-track screen IS the news "listing").
            if playerVM.currentChannel?.preferredSource == "podcast",
               let date = track.bestDate {
                Text(date.formatted(.dateTime.year().month().day()))
                    .font(.system(size: Self.mainRegularSize))
                    .foregroundStyle(.white.opacity(0.7))
            }
            // License/source intentionally NOT shown here — only in the
            // Track Info popup — to keep the main track box uncluttered.
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        // One spoken element: "Title, Artist, Part 2 of 5" rather than four
        // separate VoiceOver stops.
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white)
            Text(playerVM.loadingMessage ?? "Loading…")
                .font(.system(size: Self.mainRegularSize))
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
                .font(.system(size: Self.mainRegularSize))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.trailing)
            Button("Try Again") {
                if let ch = playerVM.currentChannel {
                    Task { await playerVM.load(channel: ch) }
                }
            }
            .font(.system(size: Self.mainRegularSize))
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
            .font(.system(size: Self.mainRegularSize))
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
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Track Info")
                .padding(.trailing, 8)
            }
            .padding(.vertical, 2)
        } else {
            fullScrubberRow
        }
    }

    // Apple HIG: tap targets ≥ 44×44 pt. The heart and ••• used to be 16 pt
    // glyphs in roughly 24 pt tap zones — easy to miss, especially with the
    // progress bar right below. They are now 22 pt glyphs in 44×44 buttons.
    private var fullScrubberRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundStyle(isFavorite ? .red : .white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                .padding(.leading, 8)

                if let dur = playerVM.trackDuration, dur > 0 {
                    Text(formatTime(playerVM.currentPosition))
                        .font(.system(size: Self.mainRegularSize))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.leading, 6)
                        // The progress bar below carries the spoken position.
                        .accessibilityHidden(true)
                }

                Spacer()

                if let dur = playerVM.trackDuration, dur > 0 {
                    Text("-" + formatTime(max(0, dur - playerVM.currentPosition)))
                        .font(.system(size: Self.mainRegularSize))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.trailing, 6)
                        .accessibilityHidden(true)
                }

                Button { showMoreOptions = true } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More Options")
                .padding(.trailing, 8)
            }

            if let dur = playerVM.trackDuration, dur > 0 {
                progressBar(duration: dur)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 2)
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
                        playerVM.isScrubbing = true
                        let f = min(max(Double(v.location.x / w), 0), 1)
                        scrubFraction = f
                        playerVM.currentPosition = f * duration
                    }
                    .onEnded { v in
                        let f = min(max(Double(v.location.x / w), 0), 1)
                        playerVM.seek(to: f * duration)
                        scrubFraction = nil
                        playerVM.isScrubbing = false
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
                            if playerVM.currentTrackIsMultiPart {
                                NavigationLink {
                                    ChapterListView(onDismiss: { showMoreOptions = false })
                                        .environmentObject(playerVM)
                                } label: {
                                    Label("Chapter List", systemImage: "list.number")
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
    // "Phantom" repeat-one toggle in the wheel's center. Never enabled for
    // ambient loops (they already repeat). The glyph only shows when on.
    var repeatEnabled: Bool = false
    var repeatOn: Bool = false
    var onRepeatToggle: () -> Void = {}
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

            ZStack {
                // Outer ring — flat metallic. (The elapsed-progress arc/thumb
                // was removed — progress lives on the track box's bar now.)
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

                // Center — also the phantom Repeat-One toggle. The glyph only
                // appears while repeat is engaged ("selected"); tapping the
                // center again clears it and the glyph vanishes.
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: innerR * 2, height: innerR * 2)
                    .allowsHitTesting(false)

                if repeatEnabled && repeatOn {
                    Image(systemName: "repeat.1")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .allowsHitTesting(false)
                }

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

                        guard dist <= outerR else { return }
                        // Center = phantom Repeat-One toggle.
                        if dist <= innerR {
                            if repeatEnabled {
                                tapTrigger += 1
                                onRepeatToggle()
                            }
                            return
                        }

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
            .accessibilityLabel("Playback controls")
            .accessibilityValue(isPlaying ? "Playing" : "Paused")
            .accessibilityHint(duration > 0
                ? "Swipe up or down to seek by 15 seconds. Use the rotor actions for menu, skip and repeat."
                : "Use the rotor actions for menu and play or pause.")
            .accessibilityAction(.default) { onPlayPause() }
            .accessibilityActions {
                Button(isPlaying ? "Pause" : "Play") { onPlayPause() }
                Button("Open Menu") { onMenu() }
                if transportEnabled {
                    Button("Next Track") { onForward() }
                    Button("Previous Track") { onBack() }
                }
                if repeatEnabled {
                    Button(repeatOn ? "Turn Off Repeat One" : "Repeat This Track") {
                        onRepeatToggle()
                    }
                }
            }
            .accessibilityAdjustableAction { direction in
                guard duration > 0 else { return }
                switch direction {
                case .increment: onSeek(min(duration, currentTime + 15))
                case .decrement: onSeek(max(0, currentTime - 15))
                @unknown default: break
                }
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
