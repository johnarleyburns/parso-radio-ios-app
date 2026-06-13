import SwiftUI

struct NowPlayingScreen: View {
    let dismiss: () -> Void

    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @EnvironmentObject var favorites: FavoritesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var envDismiss
    @State private var showChapters = false
    @State private var chapterListItems: [Track] = []
    @State private var chapterListLoading = false
    @State private var sleepTimerNow: Date = Date()
    private static let sleepTimerOptions: [Int] = [15, 30, 45, 60]
    @State private var showTrackAlbumInfo = false
    @State private var trackAlbumTitle = ""
    @State private var trackAlbumParts: [Track] = []
    @State private var trackAlbumParentId: String?
    @State private var showAddToPlaylist = false
    @State private var showAddItemToPlaylist = false
    @State private var showMoreOptions = false
    @State private var showFullMetadata = false
    @State private var isCurrentFavorite = false
    @State private var showShareActionSheet = false
    @State private var enrichedMeta: TrackMetadata?
    @ObservedObject private var kids = KidsModeController.shared
    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore
    @AppStorage("supporterBadgeHidden") private var supporterBadgeHidden = false
    @State private var showContributionSupport = false
    @State private var scrubFraction: Double? = nil

    private var displayChannel: Channel {
        playerVM.currentChannel ?? Channel.defaults.first(where: { $0.id == "guitar-classical" }) ?? Channel.defaults[0]
    }

    private var isAmbientLoop: Bool {
        playerVM.currentChannel?.mediaKind == .ambient
    }

    private var ambientVideoURL: URL? {
        guard isAmbientLoop else { return nil }
        return AmbientStaticService.bundledVideoURL(
            forChannelId: playerVM.currentChannel?.id ?? "")
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

                    // Track metadata below the image — always reserve space so
                    // the channel name doesn't jump when a track loads.
                    Group {
                        if let track = playerVM.currentTrack, !isAmbientLoop {
                            Button {
                                if track.parentIdentifier != nil || track.isMultiPart == true {
                                    Task { await openTrackAlbumDetail() }
                                } else {
                                    showMoreOptions = true
                                }
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
                        }
                    }
                    .frame(minHeight: 54)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    Spacer()

                    transportControls
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
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
        .sheet(isPresented: $showTrackAlbumInfo) {
            NowPlayingAlbumDetailView(
                title: trackAlbumTitle,
                tracks: trackAlbumParts,
                parentIdentifier: trackAlbumParentId
            )
            .environmentObject(playerVM)
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

    // MARK: - Favorites & Share Buttons

    private var favoriteHeartButton: some View {
        Button {
            guard let track = playerVM.currentTrack else { return }
            Task {
                let ch = playerVM.currentChannel
                let chapterIdx = track.partNumber
                await favorites.toggle(
                    track: track,
                    channel: ch,
                    positionSeconds: playerVM.currentPosition,
                    chapterIndex: chapterIdx
                )
                isCurrentFavorite = await favorites.isFavorited(track: track, channel: ch)
            }
        } label: {
            Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                .font(.system(size: 18))
                .foregroundStyle(isCurrentFavorite ? .red : .accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCurrentFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private var shareButton: some View {
        Button {
            if isBookChannel, let track = playerVM.currentTrack {
                shareBook(track)
            } else if let track = playerVM.currentTrack {
                if track.parentIdentifier != nil || track.isMultiPart == true {
                    showShareActionSheet = true
                } else {
                    shareTrack(track)
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
        .confirmationDialog("Share", isPresented: $showShareActionSheet) {
            if let track = playerVM.currentTrack {
                Button("Share Track") { shareTrack(track) }
                Button("Share \(isBookChannel ? "Book" : "Album")") { shareAlbumOrBook(track) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func shareTrack(_ track: Track) {
        guard let url = ShareURLBuilder.url(for: track) else { return }
        let activityVC = UIActivityViewController(activityItems: [url, track.title], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }

    private func shareBook(_ track: Track) {
        shareAlbumOrBook(track)
    }

    private func shareAlbumOrBook(_ track: Track) {
        let id = track.parentIdentifier ?? track.id
        guard let url = URL(string: "https://archive.org/details/\(id)") else { return }
        let activityVC = UIActivityViewController(activityItems: [url, track.title], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        VStack(spacing: 12) {
            if !isAmbientLoop, let dur = playerVM.trackDuration, dur > 0 {
                if !kids.isEnabled {
                    HStack(spacing: 0) {
                        favoriteHeartButton
                        Spacer()
                        shareButton
                    }
                    .padding(.horizontal, 4)
                }

                HStack(spacing: 0) {
                    Text(playerVM.currentPosition.formattedTime)
                        .font(.system(size: mainRegularSize))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("-" + max(0, dur - playerVM.currentPosition).formattedTime)
                        .font(.system(size: mainRegularSize))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                progressBar(duration: dur)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 0) {
                if !isAmbientLoop {
                    Button {
                        playerVM.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18))
                            .foregroundStyle(playerVM.shuffleMode ? .blue : .secondary)
                    }
                    .accessibilityLabel(playerVM.shuffleMode ? "Shuffle on" : "Shuffle off")
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                }

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

                if !isAmbientLoop {
                    Button {
                        playerVM.toggleRepeat()
                    } label: {
                        Image(systemName: "repeat.1")
                            .font(.system(size: 18))
                            .foregroundStyle(playerVM.repeatMode == .one ? .blue : .secondary)
                    }
                    .accessibilityLabel(playerVM.repeatMode == .one ? "Repeat on" : "Repeat off")
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 4)

            if !isAmbientLoop {
                HStack(spacing: 12) {
                    playbackSpeedRow
                    sleepTimerRow
                    AirPlayButton()
                        .frame(width: 32, height: 32)
                }
                .padding(.horizontal, 12)
            }
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
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isAmbientLoop, playerVM.currentTrack != nil {
                HStack(spacing: 8) {
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
        .overlay {
            if !isAmbientLoop, playerVM.currentTrack != nil {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { playerVM.seekBy(-10) }
                        .accessibilityLabel("Skip back 10 seconds")
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { playerVM.seekBy(10) }
                        .accessibilityLabel("Skip forward 10 seconds")
                }
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
                } else if let chImage = channelFallbackImage {
                    Image(uiImage: chImage)
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

    private var channelFallbackImage: UIImage? {
        let ch = playerVM.currentChannel ?? displayChannel
        if let img = UIImage(named: ch.id) { return img }
        // User-added podcasts: resolve via built-in name match
        if ch.id.hasPrefix("podcast-"),
           let builtIn = Channel.defaults.first(where: {
               $0.name == ch.name && $0.category == "Podcasts" && !$0.id.hasPrefix("podcast-")
           }),
           let img = UIImage(named: builtIn.id) {
            return img
        }
        return nil
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

            if playerVM.currentChannel?.mediaKind != .music {
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

            if playerVM.currentChannel?.mediaKind == .podcast,
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

    private var isBookChannel: Bool {
        let cat = playerVM.currentChannel?.category
        return cat == "Audiobooks" || cat == "Curated Books"
    }

    private var isChapterItem: Bool {
        guard let track = playerVM.currentTrack,
              track.source == "internet_archive" else { return false }
        if isBookChannel { return true }
        let haystack = (track.tags.joined(separator: " ") + " " + track.id).lowercased()
        return haystack.contains("librivox")
    }

    private var sheetNavigationTitle: String {
        if isBookChannel { return "Book" }
        return "Album"
    }

    private var albumIAImageURL: URL? {
        guard let track = playerVM.currentTrack,
              track.source == "internet_archive" else { return nil }
        let id = track.parentIdentifier ?? track.id
        return URL(string: "https://archive.org/services/img/\(id)")
    }

    private var albumIADetailsURL: URL? {
        guard let track = playerVM.currentTrack,
              track.source == "internet_archive" else { return nil }
        let id = track.parentIdentifier ?? track.id
        return URL(string: "https://archive.org/details/\(id)")
    }

    private func shareAlbumURL(for track: Track) -> URL? {
        if track.source == "internet_archive" {
            let id = track.parentIdentifier ?? track.id
            return URL(string: "https://archive.org/details/\(id)")
        }
        return ShareURLBuilder.url(for: track)
    }

    private var fallbackAlbumImage: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: isBookChannel ? "book.fill" : "music.note")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
            }
    }

    private var combinedTrackSheet: some View {
        NavigationStack {
            List {
                if let track = playerVM.currentTrack {
                    Section {
                        if let url = albumIAImageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    fallbackAlbumImage
                                }
                            }
                        } else {
                            fallbackAlbumImage
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)

                    Section {
                        if isBookChannel {
                            SharedViews.infoRow("Name", playerVM.itemDisplayName(for: track))
                            if let a = cleaned(track.artist) { SharedViews.infoRow("Author", a) }
                        } else {
                            SharedViews.infoRow("Name", playerVM.itemDisplayName(for: track))
                            if let a = cleaned(track.artist) { SharedViews.infoRow("Artist", a) }
                            if let c = cleaned(track.composer) { SharedViews.infoRow("Composer", c.capitalized) }
                        }

                        if let date = track.bestDate {
                            SharedViews.infoRow(track.dateLabel, date.formatted(.dateTime.year().month().day()))
                        }
                        if let meta = enrichedMeta {
                            if let work = meta.workTitle { SharedViews.infoRow("Work", work) }
                            if let performer = meta.performer { SharedViews.infoRow("Performer", performer) }
                            if let composer = meta.composer, composer != track.composer { SharedViews.infoRow("Composer (enriched)", composer) }
                            if let catNo = meta.catalogNumber { SharedViews.infoRow("Catalog No.", catNo) }
                            if let bio = meta.authorBio, !bio.isEmpty { SharedViews.infoRow("Author Bio", bio) }
                            if !meta.genreTags.isEmpty { SharedViews.infoRow("Genres", meta.genreTags.joined(separator: ", ")) }
                        }
                        DisclosureGroup(isBookChannel ? "More about this book..." : "More about this album...", isExpanded: $showFullMetadata) {
                            ForEach(fullMetadata(track), id: \.0) { pair in
                                SharedViews.infoRow(pair.0, pair.1)
                            }
                        }
                    }

                    if !isAmbientLoop {
                        if playerVM.currentTrackIsMultiPart {
                            Section(isBookChannel ? "Chapters" : "Tracks") {
                                explodedChapterList
                            }
                        }

                        if playerVM.currentTrackIsMultiPart {
                            Section {
                                Button {
                                    showMoreOptions = false
                                    Task { await playerVM.playEntireCurrentItem() }
                                } label: {
                                    Label("Play Entire \(isBookChannel ? "Book" : "Album")", systemImage: "play.rectangle.fill")
                                }
                            }
                        }

                        if !kids.isEnabled {
                            bookmarksSection(for: track)

                            Section {
                                if isBookChannel, track.source == "internet_archive" {
                                    if let iaURL = albumIADetailsURL {
                                        Link(destination: iaURL) {
                                            Label("View book on archive.org", systemImage: "safari")
                                        }
                                    }
                                }

                                if !isBookChannel, track.source == "internet_archive" {
                                    if let iaURL = albumIADetailsURL {
                                        Link(destination: iaURL) {
                                            Label("View Album on archive.org", systemImage: "safari")
                                        }
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
                                        Label("Add \(isBookChannel ? "Book" : "Album") to Playlist", systemImage: "text.badge.plus")
                                    }
                                    Button {
                                        showMoreOptions = false
                                        let nm = playerVM.itemDisplayName(for: track)
                                        Task {
                                            await playerVM.addEntireItemToNewPlaylist(from: track, named: nm, using: playlistVM)
                                        }
                                    } label: {
                                        Label("Add \(isBookChannel ? "Book" : "Album") to New Playlist \"\(shortName(playerVM.itemDisplayName(for: track)))\"", systemImage: "rectangle.stack.badge.plus")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(sheetNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showMoreOptions = false }
                }
            }
            .task(id: playerVM.currentTrack?.id) {
                if let t = playerVM.currentTrack {
                    isCurrentFavorite = await favorites.isFavorited(track: t, channel: playerVM.currentChannel)
                    enrichedMeta = await playerVM.db.fetchTrackMetadata(trackID: t.id)
                } else {
                    enrichedMeta = nil
                }
            }
        }
    }

    // MARK: - Playback Controls

    private var explodedChapterList: some View {
        Group {
            if chapterListLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if chapterListItems.isEmpty {
                Text("No items")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(chapterListItems) { item in
                    Button {
                        showMoreOptions = false
                        Task { await playerVM.playRecentTrack(item) }
                    } label: {
                        HStack(spacing: 8) {
                            if let pn = item.partNumber {
                                Text("\(pn)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 24, alignment: .trailing)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.body)
                                    .lineLimit(2)
                                    .foregroundStyle(playerVM.currentTrack?.id == item.id ? Color.accentColor : .primary)
                                    .fontWeight(playerVM.currentTrack?.id == item.id ? .bold : .regular)
                                if item.duration > 0 {
                                    Text(item.duration.formattedTime)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if playerVM.currentTrack?.id == item.id {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        playerVM.currentTrack?.id == item.id
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                }
            }
        }
        .task {
            chapterListLoading = true
            chapterListItems = await playerVM.fetchCurrentItemChapters() ?? []
            chapterListLoading = false
        }
    }

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
            Section("Sleep Timer") {
                ForEach(Self.sleepTimerOptions, id: \.self) { mins in
                    Button("\(mins) minutes") { playerVM.startSleepTimer(minutes: mins) }
                }
                Button("End of Track") { playerVM.setSleepAtEndOfTrack(true) }
            }
            if active {
                Section {
                    Button(role: .destructive) {
                        playerVM.cancelSleepTimer()
                    } label: { Text("Cancel Sleep Timer") }
                }
            }
        } label: {
            Image(systemName: active ? "moon.fill" : "moon")
                .font(.system(size: 16))
                .frame(width: 32, height: 32)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            sleepTimerNow = now
        }
        .accessibilityLabel(active ? "Sleep timer, \(sleepTimerStatus)" : "Sleep timer")
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

    private func shortName(_ s: String, max: Int = 26) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "…" : s
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
        if !track.tags.isEmpty { add("Subjects", track.tags.joined(separator: ", ")) }
        if !track.instruments.isEmpty { add("Instruments", track.instruments.joined(separator: ", ")) }
        if track.rawCreator != track.artist { add("Raw creator", track.rawCreator) }
        if let rec = track.recordingDate { add("Recorded", rec.formatted(.dateTime.year().month().day())) }
        if let downloadURL = track.downloadURL { add("Download URL", downloadURL.absoluteString) }
        if track.localFilePath != nil { add("Downloaded", "Yes") }
        add("Quality score", String(format: "%.2f", track.qualityScore))
        add("Metadata confidence", String(format: "%.2f", track.metadataConfidence))
        add("Stream URL", track.streamURL.absoluteString)
        return rows
    }

    private func openTrackAlbumDetail() async {
        guard let track = playerVM.currentTrack else { return }
        let identifier = track.parentIdentifier ?? track.id
        guard let parts = await playerVM.resolveItemParts(identifier: identifier),
              !parts.isEmpty else {
            showMoreOptions = true
            return
        }
        trackAlbumParts = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        trackAlbumParentId = identifier
        trackAlbumTitle = track.artist + " — " + track.title
        showTrackAlbumInfo = true
    }

    @ViewBuilder
    private var miniPlayerOverlay: some View {
        if let track = playerVM.currentTrack {
            HStack(spacing: 12) {
                ArtworkThumbnail(track: track, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline).fontWeight(.semibold).lineLimit(1)
                    Text(track.artist)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    playerVM.togglePlayPause()
                } label: {
                    Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(playerVM.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.thinMaterial)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(.separator), alignment: .top)
        }
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
