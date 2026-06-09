import SwiftUI

struct NowPlayingScreen: View {
    let dismiss: () -> Void

    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var envDismiss
    @State private var showChapters = false
    @State private var sleepTimerNow: Date = Date()
    private static let sleepTimerOptions: [Int] = [15, 30, 45, 60]
    @State private var showChannelInfo = false
    @State private var showAddToPlaylist = false
    @State private var showAddItemToPlaylist = false
    @State private var showMoreOptions = false
    @State private var showFullMetadata = false
    @State private var isCurrentTrackFavorite = false
    @ObservedObject private var kids = KidsModeController.shared
    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore
    @AppStorage("supporterBadgeHidden") private var supporterBadgeHidden = false
    @State private var showContributionSupport = false
    @State private var scrubFraction: Double? = nil

    private var displayChannel: Channel {
        playerVM.currentChannel ?? Channel.defaults.first(where: { $0.id == "guitar-classical" }) ?? Channel.defaults[0]
    }

    private var isAmbientLoop: Bool {
        playerVM.currentChannel?.contentType == .ambientLoop
    }

    private var ambientVideoURL: URL? {
        guard isAmbientLoop else { return nil }
        return AmbientStaticService.bundledVideoURL(
            forChannelId: playerVM.currentChannel?.id ?? "")
    }

    private var titleIcon: String? {
        if let pl = playerVM.currentPlaylist {
            return pl.isFavorites ? "heart.fill" : "music.note.list"
        }
        return playerVM.currentChannel?.icon
    }

    private var titleText: String {
        playerVM.currentPlaylist?.name ?? playerVM.currentChannel?.name ?? ""
    }

    @ScaledMetric(relativeTo: .title3)      private var mainBoldSize: CGFloat = 19
    @ScaledMetric(relativeTo: .subheadline) private var mainRegularSize: CGFloat = 14
    private static let progressBlue = Color(red: 0.18, green: 0.42, blue: 0.95)

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    screenPanel(geo: geo)
                        .frame(height: max(160, geo.size.height * 0.55))
                        .padding(.top, 16)

                    // Track metadata below the image
                    if let track = playerVM.currentTrack, !isAmbientLoop {
                        Button {
                            showMoreOptions = true
                        } label: {
                            VStack(spacing: 4) {
                                Text(track.title)
                                    .font(.system(size: mainBoldSize, weight: .bold))
                                    .lineLimit(2)
                                if let artist = cleaned(track.artist) {
                                    Text(artist)
                                        .font(.system(size: mainRegularSize))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens track info")
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }

                    Spacer()

                    transportControls
                        .padding(.horizontal, 24)

                    Spacer(minLength: 16)
                }
                .frame(maxWidth: min(geo.size.width, horizontalSizeClass == .regular ? 480 : geo.size.width))
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                playerVM.saveCurrentSpot()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 8)
            .padding(.leading, 16)
            .accessibilityLabel("Back to Browse")
        }
        .overlay(alignment: .top) {
            Button {
                showChannelInfo = true
            } label: {
                HStack(spacing: 6) {
                    if let icon = titleIcon {
                        Image(systemName: icon)
                            .foregroundStyle(.blue)
                    }
                    Text(titleText)
                        .foregroundStyle(.blue)
                }
                .font(.system(size: mainBoldSize, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 70)
                .padding(.vertical, 10)
            }
            .padding(.top, 6)
            .accessibilityHint("Opens channel info")
        }
        .overlay(alignment: .topTrailing) {
            if playerVM.currentTrack != nil, !isAmbientLoop {
                Button {
                    showMoreOptions = true
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
                .accessibilityLabel("Track Info")
            }
        }
        .sheet(isPresented: $showChannelInfo) {
            NavigationStack {
                ChannelInfoView(channel: displayChannel)
            }
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
        .sheet(isPresented: $showContributionSupport) {
            NavigationStack {
                ContributionSupportView(store: ParsoMusicApp.sharedContributionStore, showsDoneButton: true)
            }
        }
        .alert("You're Offline", isPresented: Binding(
            get: { playerVM.transientMessage != nil },
            set: { if !$0 { playerVM.transientMessage = nil } }
        )) {
            Button("OK", role: .cancel) { playerVM.transientMessage = nil }
        } message: {
            Text(playerVM.transientMessage ?? "")
        }
        .onChange(of: showMoreOptions) { _, shown in
            if !shown { playerVM.isScrubbing = false }
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        VStack(spacing: 20) {
            if !isAmbientLoop, let dur = playerVM.trackDuration, dur > 0 {
                progressBar(duration: dur)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 0) {
                Spacer()

                if !isAmbientLoop {
                    Button {
                        Task { await playerVM.goToPreviousTrack() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 30))
                    }
                    .accessibilityLabel("Previous track")
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    playerVM.togglePlayPause()
                } label: {
                    Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }
                .accessibilityLabel(playerVM.isPlaying ? "Pause" : "Play")
                .buttonStyle(.plain)

                Spacer()

                if !isAmbientLoop {
                    Button {
                        playerVM.skip()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 30))
                    }
                    .accessibilityLabel("Next track")
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Progress Bar

    private func progressBar(duration: Double) -> some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let frac = scrubFraction
                ?? min(max(playerVM.currentPosition / duration, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.2)).frame(height: 5)
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
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(playerVM.currentPosition.formattedTime) of \(duration.formattedTime)")
        .accessibilityHint("Swipe up or down to seek by 15 seconds")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                playerVM.seek(to: min(duration, playerVM.currentPosition + 15))
            case .decrement:
                playerVM.seek(to: max(0, playerVM.currentPosition - 15))
            @unknown default: break
            }
        }
    }

    // MARK: - Screen Panel

    private func screenPanel(geo: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            artworkBackground

            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top, endPoint: .center
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.82)],
                startPoint: .center, endPoint: .bottom
            )

            VStack(spacing: 0) {
                if isAmbientLoop {
                    EmptyView()
                } else if let err = playerVM.errorMessage {
                    errorView(err)
                }

                if !isAmbientLoop {
                    HStack(spacing: 0) {
                        Text(playerVM.currentPosition.formattedTime)
                            .font(.system(size: mainRegularSize))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        if let dur = playerVM.trackDuration, dur > 0 {
                            Text("-" + max(0, dur - playerVM.currentPosition).formattedTime)
                                .font(.system(size: mainRegularSize))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isAmbientLoop, playerVM.currentTrack != nil {
                HStack(spacing: 8) {
                    if playerVM.shuffleMode {
                        statusBadge("shuffle", tint: .blue, label: "Shuffle is on")
                    }
                    if playerVM.repeatMode == .one {
                        statusBadge("repeat.1", tint: .blue, label: "Repeat track is on")
                    }
                }
                .padding(.top, 60)
                .padding(.trailing, 12)
            }
        }
        .overlay {
            if playerVM.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(width: 80, height: 80)
                    .background(.black.opacity(0.5), in: Circle())
                    .transition(.opacity)
                    .accessibilityLabel("Loading")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .dynamicTypeSize(.medium ... .accessibility2)
        .contextMenu {
            if playerVM.currentTrack != nil, !isAmbientLoop, !kids.isEnabled {
                Button { showAddToPlaylist = true } label: {
                    Label("Add to Playlist", systemImage: "plus.circle")
                }
            }
        }
    }

    private var artworkBackground: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [ChannelCategoryStyle.color(for: displayChannel.category).opacity(0.6),
                             ChannelCategoryStyle.color(for: displayChannel.category).opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if isAmbientLoop, let video = ambientVideoURL {
                    LoopingVideoView(
                        url: video,
                        horizontalAnchor: playerVM.currentChannel?.id == "ambient-rain" ? 1.0 : 0.5,
                        isPlaying: playerVM.isPlaying)
                } else if let art = playerVM.currentArtwork {
                    Image(uiImage: art)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProceduralVisualizerView(
                        seed: playerVM.currentTrack?.id ?? displayChannel.id,
                        isPlaying: playerVM.isPlaying)
                }
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8),
                       value: playerVM.currentTrack?.id)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func trackMetadataStack(track: Track) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
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

            if playerVM.currentChannel?.contentType != .music {
                if let part = track.partNumber, let total = track.totalParts, total > 1 {
                    Text("Part \(part) of \(total)")
                        .font(.system(size: mainRegularSize))
                        .foregroundStyle(.white.opacity(0.7))
                } else if playerVM.currentItemChapterCount > 1 {
                    Text(playerVM.currentItemPartIndex.map {
                        "Part \($0) of \(playerVM.currentItemChapterCount)"
                    } ?? "\(playerVM.currentItemChapterCount) parts")
                        .font(.system(size: mainRegularSize))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if playerVM.currentChannel?.preferredSource == "podcast",
               let date = track.bestDate {
                Text(date.formatted(.dateTime.year().month().day()))
                    .font(.system(size: mainRegularSize))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
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

    // MARK: - Combined Track Info Sheet

    private var combinedTrackSheet: some View {
        NavigationStack {
            List {
                if let track = playerVM.currentTrack {
                    Section("Now Playing") {
                        SharedViews.infoRow("Title", track.title)
                        if let a = cleaned(track.artist) { SharedViews.infoRow("Artist", a) }
                        if let c = cleaned(track.composer) { SharedViews.infoRow("Composer", c.capitalized) }
                        if let dur = trackInfoDuration(track) {
                            SharedViews.infoRow("Duration", dur.formattedTime)
                        }
                        if playerVM.currentTrackIsMultiPart, playerVM.currentItemChapterCount > 1 {
                            SharedViews.infoRow(isLectureChannel ? "Lectures" : (usesChapterTerminology ? "Chapters" : "Tracks"), "\(playerVM.currentItemChapterCount)")
                            if playerVM.currentItemTotalDuration > 0 {
                                SharedViews.infoRow("Total Time", playerVM.currentItemTotalDuration.formattedTime)
                            }
                            if let idx = playerVM.currentItemPartIndex {
                                SharedViews.infoRow(isLectureChannel ? "Lecture" : (usesChapterTerminology ? "Chapter" : "Track"), "\(idx) of \(playerVM.currentItemChapterCount)")
                            }
                        }
                        if let date = track.bestDate {
                            SharedViews.infoRow(track.dateLabel, date.formatted(.dateTime.year().month().day()))
                        }
                        DisclosureGroup("Full Metadata", isExpanded: $showFullMetadata) {
                            ForEach(fullMetadata(track), id: \.0) { pair in
                                SharedViews.infoRow(pair.0, pair.1)
                            }
                        }
                    }

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
                            Toggle(isOn: Binding(
                                get: { playerVM.repeatMode == .one },
                                set: { on in
                                    if (playerVM.repeatMode == .one) != on { playerVM.toggleRepeat() }
                                }
                            )) {
                                Label("Repeat Track", systemImage: "repeat.1")
                            }
                            if playerVM.currentTrackIsMultiPart {
                                NavigationLink {
                                    ChapterListView(onDismiss: { showMoreOptions = false })
                                        .environmentObject(playerVM)
                                } label: {
                                    Label(isLectureChannel ? "Lecture List" : (usesChapterTerminology ? "Chapter List" : "Track List"), systemImage: "list.number")
                                }
                            }
                            HStack {
                                Label("AirPlay", systemImage: "airplayaudio")
                                Spacer()
                                AirPlayButton()
                                    .frame(width: 32, height: 32)
                            }
                        }

                        if playerVM.currentTrackIsMultiPart {
                            Section {
                                Button {
                                    showMoreOptions = false
                                    Task { await playerVM.playEntireCurrentItem() }
                                } label: {
                                    Label("Play Entire \(itemKindLabel(track))", systemImage: "play.rectangle.fill")
                                }
                            }
                        }

                        if !kids.isEnabled {
                            bookmarksSection(for: track)

                            Section {
                                if let shareURL = shareURL(for: track) {
                                    ShareLink(item: shareURL, message: Text(track.title)) {
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
                                        Label("Add \(itemKindLabel(track)) to Playlist", systemImage: "text.badge.plus")
                                    }
                                    Button {
                                        showMoreOptions = false
                                        let nm = playerVM.itemDisplayName(for: track)
                                        Task {
                                            await playerVM.addEntireItemToNewPlaylist(from: track, named: nm, using: playlistVM)
                                        }
                                    } label: {
                                        Label("Add \(itemKindLabel(track)) to New Playlist \"\(shortName(playerVM.itemDisplayName(for: track)))\"", systemImage: "rectangle.stack.badge.plus")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isLectureChannel ? "Lecture Info" : (usesChapterTerminology ? "Chapter Info" : "Track Info"))
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

    // MARK: - Playback Controls

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
    }

    private func rateLabel(_ r: Double) -> String {
        if r.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(r))x" }
        return String(format: "%gx", r)
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            sleepTimerNow = now
        }
        .accessibilityLabel("Sleep timer, currently \(sleepTimerStatus)")
    }

    private var sleepTimerStatus: String {
        if playerVM.sleepAtEndOfTrack { return "End of Track" }
        if let ends = playerVM.sleepTimerEndsAt {
            let remaining = max(0, ends.timeIntervalSince(sleepTimerNow))
            return remaining.formattedTime
        }
        return "Off"
    }

    @ViewBuilder
    private func bookmarksSection(for track: Track) -> some View {
        Section("Bookmarks") {
            Button {
                Task { await playerVM.addBookmarkAtCurrentPosition() }
            } label: {
                Label("Bookmark This Spot (\(playerVM.currentPosition.formattedTime))", systemImage: "bookmark")
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bm.label ?? bm.positionSeconds.formattedTime)
                                .font(.body)
                            if bm.label != nil {
                                Text(bm.positionSeconds.formattedTime)
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

    private func shareURL(for track: Track) -> URL? {
        ShareURLBuilder.url(for: track)
    }

    private func trackInfoDuration(_ track: Track) -> Double? {
        if let d = playerVM.trackDuration, d > 0 { return d }
        return track.duration > 0 ? track.duration : nil
    }

    private func shortName(_ s: String, max: Int = 26) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }

    private var usesChapterTerminology: Bool {
        if playerVM.currentChannel?.category == "Lectures" { return true }
        guard let t = playerVM.currentTrack else { return false }
        return itemKindLabel(t) == "Book"
    }

    private var isLectureChannel: Bool {
        playerVM.currentChannel?.category == "Lectures"
    }

    private func itemKindLabel(_ track: Track) -> String {
        if playerVM.currentChannel?.category == "Lectures" { return "Series" }
        if playerVM.currentChannel?.category == "Audiobooks" { return "Book" }
        let hay = (track.parentIdentifier ?? track.id).lowercased()
        if hay.contains("librivox") || track.tags.contains(where: {
            $0.contains("librivox") || $0.contains("audiobook")
        }) { return "Book" }
        return "Album"
    }

    private func fullMetadata(_ track: Track) -> [(String, String)] {
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !v.isEmpty, v.lowercased() != "unknown" else { return }
            rows.append((label, v))
        }
        add("License", LicenseDisplay.name(track.license))
        add("Source", SourceDisplay.name(track.source))
        add("Identifier", track.id)
        if let part = track.partNumber, let total = track.totalParts, total > 1 {
            add("Part", "\(part) of \(total)")
        }
        add("Item", track.parentIdentifier)
        if let multi = track.isMultiPart { add("Multi-part item", multi ? "Yes" : "No") }
        if !track.tags.isEmpty { add("Tags", track.tags.joined(separator: ", ")) }
        if !track.instruments.isEmpty { add("Instruments", track.instruments.joined(separator: ", ")) }
        if track.rawCreator != track.artist { add("Raw creator", track.rawCreator) }
        if let added = track.addedDate { add("Added", added.formatted(.dateTime.year().month().day())) }
        if let rec = track.recordingDate { add("Recorded", rec.formatted(.dateTime.year().month().day())) }
        add("Quality score", String(format: "%.2f", track.qualityScore))
        add("Metadata confidence", String(format: "%.2f", track.metadataConfidence))
        add("Stream URL", track.streamURL.absoluteString)
        add("Local file", track.localFilePath)
        return rows
    }

    private func cleaned(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !v.isEmpty, v.lowercased() != "unknown" else { return nil }
        return v
    }
}

#Preview {
    let db = try! DatabaseService(path: ":memory:")
    let dm = DownloadManager(db: db)
    NowPlayingScreen(dismiss: {})
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
