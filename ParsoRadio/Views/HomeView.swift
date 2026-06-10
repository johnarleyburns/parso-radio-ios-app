import SwiftUI

// MARK: - Navigation Routes

enum HomeRoute: Hashable {
    case playlist(Playlist)
    case channelInfo(Channel)
    case channelCategory(String)
    case playlists
    case recentlyPlayed
    case settings
    case about
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var path: [HomeRoute] = []
    @State private var showPlayer = false

    @StateObject private var searchVM = SearchViewModel()
    @State private var searchText = ""
    @State private var searchActive = false

    @ObservedObject private var kids = KidsModeController.shared
    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore
    @State private var showContributionSupport = false

    // Live Music on This Day
    @State private var dailyLiveEntry: LiveMusicEntry?
    @State private var showLiveDetail = false
    @State private var liveMusicLoading = true
    private let liveMusicService = LiveMusicOnThisDayService()

    // Recently Added Audiobooks
    @State private var dailyAudiobook: AudiobookEntry?
    @State private var showAudiobookDetail = false
    @State private var audiobookLoading = true
    private let audiobookService = RecentlyAddedAudiobooksService()

    // Session restore
    @State private var pendingChannel: Channel = {
        let raw = UserDefaults.standard.string(forKey: "lastChannelId") ?? "guitar-classical"
        let lastId = PlayerViewModel.migratedChannelId(raw) ?? raw
        return Channel.defaults.first { $0.id == lastId } ?? Channel.defaults[0]
    }()

    private static let categoryOrder = [
        "Curated", "Ambient", "Podcasts", "Audiobooks", "Curated Books", "Lectures"
    ]

    static func orderedCategories() -> [String] {
        let present = Set(Channel.defaults.map(\.category))
        return categoryOrder.filter(present.contains)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if searchActive {
                    searchResultsContent
                } else {
                    homeGrid
                }
            }
            .refreshable {
                liveMusicService.clearCachedEntry()
                if let e = await liveMusicService.fetchDailyEntry(forceFresh: true) {
                    dailyLiveEntry = e
                }
                if let a = await audiobookService.fetchDailyEntry(forceFresh: true) {
                    dailyAudiobook = a
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lorewave")
            .toolbar {
                if contributionStore.isSupporter, contributionStore.hasActiveSubscription {
                    ToolbarItem(placement: .topBarTrailing) {
                        if let uiImage = UIImage(named: "supporter") {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 28)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                                .onTapGesture { showContributionSupport = true }
                        }
                    }
                }
            }
            .searchable(text: $searchText,
                        isPresented: $searchActive,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search music, audiobooks, lectures…")
            .onSubmit(of: .search) {
                searchVM.query = searchText
                searchVM.searchChanged()
            }
            .onChange(of: searchActive) { _, active in
                if !active {
                    searchText = ""
                    searchVM.query = ""
                    searchVM.results = []
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .playlist(let pl):
                    PlaylistDetailView(playlist: pl, dismissAll: { showPlayer = true })
                        .environmentObject(playlistVM)
                        .environmentObject(playerVM)
                        .environmentObject(offlineService)
                case .channelInfo(let ch):
                    ChannelInfoView(channel: ch)
                case .channelCategory(let category):
                    channelCategoryView(for: category)
                case .playlists:
                    playlistsSubView
                case .recentlyPlayed:
                    RecentlyPlayedScreen(dismissAll: { showPlayer = true })
                        .environmentObject(playerVM)
                case .settings:
                    SettingsView()
                        .environmentObject(playerVM)
                        .environmentObject(playlistVM)
                        .environmentObject(offlineService)
                case .about:
                    AboutView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if playerVM.currentTrack != nil {
                    miniPlayer
                }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            NowPlayingScreen(dismiss: {
                if let cat = playerVM.currentChannel?.category,
                   cat != "For You",
                   path.last != .channelCategory(cat) {
                    path.append(.channelCategory(cat))
                }
                showPlayer = false
            })
                .environmentObject(playerVM)
                .environmentObject(playlistVM)
                .environmentObject(offlineService)
        }
        .sheet(isPresented: $showLiveDetail) {
            if let entry = dailyLiveEntry {
                LiveMusicDetailView(entry: entry)
                    .environmentObject(playerVM)
                    .environmentObject(playlistVM)
            }
        }
        .sheet(isPresented: $showAudiobookDetail) {
            if let entry = dailyAudiobook {
                AudiobookDetailView(entry: entry)
                    .environmentObject(playerVM)
                    .environmentObject(playlistVM)
            }
        }
        .onChange(of: kids.isEnabled) { _, enabled in
            guard enabled else { return }
            path = []
            if let target = playerVM.enterKidsMode() {
                Task { @MainActor in await playerVM.load(channel: target, autoPlay: true) }
            }
        }
        .task {
            await playlistVM.loadPlaylists()
            let entry = await liveMusicService.fetchDailyEntry()
            dailyLiveEntry = entry
            liveMusicLoading = false
            let ab = await audiobookService.fetchDailyEntry()
            dailyAudiobook = ab
            audiobookLoading = false
            UserDefaults.standard.removeObject(forKey: "wasPlayingOnQuit")

            if let pendingId = UserDefaults.standard.string(forKey: "siri.pendingChannelId"),
               let ts = UserDefaults.standard.object(forKey: "siri.pendingTimestamp") as? TimeInterval,
               Date().timeIntervalSince1970 - ts < 60 {
                UserDefaults.standard.removeObject(forKey: "siri.pendingChannelId")
                UserDefaults.standard.removeObject(forKey: "siri.pendingTimestamp")
            } else if kids.isEnabled {
                let lastId = UserDefaults.standard.string(forKey: "lastChannelId")
                let allowed = KidsModeController.allowedChannels()
                let ch = allowed.first { $0.id == lastId } ?? allowed.first ?? pendingChannel
                await playerVM.load(channel: ch, autoPlay: false)
            } else {
                await playerVM.restoreLastSession(fallbackChannel: pendingChannel, autoPlay: false)
            }
        }
    }

    // MARK: - Home Grid

    private func categoryImageName(_ category: String) -> String {
        switch category {
        case "Curated Books": return "curated"
        default: return category.lowercased()
        }
    }

    private func categoryDisplayName(_ category: String) -> String {
        switch category {
        case "Curated": return "Curated Music"
        default: return category
        }
    }

    private var homeGrid: some View {
        VStack(spacing: 0) {
            // Live Music on This Day
            if liveMusicLoading {
                loadingCard("Live Music on This Day")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else if let entry = dailyLiveEntry {
                liveMusicCard(entry)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            // Categories grid
            let ordered = Self.orderedCategories()
            let preAudiobooks = ordered.filter { $0 != "Audiobooks" && $0 != "Lectures" && $0 != "Curated Books" && $0 != "Podcasts" }
            let podcastsCategory = ordered.contains("Podcasts") ? ["Podcasts"] : []
            let postPodcasts = ordered.filter { $0 == "Audiobooks" || $0 == "Curated Books" || $0 == "Lectures" }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                categoryCard(title: "Playlists", imageName: "playlists", route: HomeRoute.playlists)

                ForEach(preAudiobooks, id: \.self) { category in
                    let imgName = categoryImageName(category)
                    let displayName = categoryDisplayName(category)
                    categoryCard(title: displayName, imageName: imgName, route: HomeRoute.channelCategory(category))
                }

                if !podcastsCategory.isEmpty {
                    let displayName = categoryDisplayName("Podcasts")
                    categoryCard(title: displayName, imageName: "podcasts", route: HomeRoute.channelCategory("Podcasts"))
                }
            }
            .padding(.horizontal, 16)

            // Audiobook card between Podcasts and Audiobooks
            if audiobookLoading {
                loadingCard("New Audiobooks")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            } else if let entry = dailyAudiobook {
                audiobookCard(entry)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(postPodcasts, id: \.self) { category in
                    let imgName = categoryImageName(category)
                    let displayName = categoryDisplayName(category)
                    categoryCard(title: displayName, imageName: imgName, route: HomeRoute.channelCategory(category))
                }

                categoryCard(title: "Settings", imageName: "settings",
                              route: HomeRoute.settings)

                categoryCard(title: "About", imageName: "about",
                              route: HomeRoute.about)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Live Music on This Day

    private func liveMusicCard(_ entry: LiveMusicEntry) -> some View {
        HStack(spacing: 0) {
            // Left side: tap for detail
            Button {
                showLiveDetail = true
            } label: {
                HStack(spacing: 12) {
                    VerifiedThumb(url: entry.thumbnailURL, fallbackName: {
                        "concert\(String(format: "%02d", Int.random(in: 1...20)))"
                    })
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contextMenu {
                            Text("IA: \(entry.thumbnailURL.absoluteString)")
                                .font(.caption)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Music on This Day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.displayName)
                            .font(.headline)
                            .lineLimit(2)
                        if let location = entry.locationSummary {
                            Text(location)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let date = entry.formattedDate {
                            Text(date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Right side: play button — enqueues full album
            Button {
                Task {
                    guard let parts = await playerVM.resolveItemParts(identifier: entry.id),
                          !parts.isEmpty else { return }
                    let ordered = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
                    await playerVM.playAlbumTracks(ordered, title: entry.displayName)
                }
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 48)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live Music on This Day: \(entry.displayName)" + (entry.locationSummary.map { " at \($0)" } ?? ""))
        .accessibilityHint("Tap left for details, tap right to play")
    }

    private func loadingCard(_ label: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Placeholder title")
                    .font(.headline).lineLimit(2)
                Text("Placeholder subtitle")
                    .font(.subheadline).lineLimit(1)
                Text("Placeholder date")
                    .font(.caption)
                ProgressView()
                    .padding(.top, 2)
            }
            .redacted(reason: .placeholder)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Recently Added Audiobooks

    private func audiobookCard(_ entry: AudiobookEntry) -> some View {
        HStack(spacing: 0) {
            Button {
                showAudiobookDetail = true
            } label: {
                HStack(spacing: 12) {
                    AudioBookThumb(entry: entry)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("New Audiobooks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.displayName)
                            .font(.headline)
                            .lineLimit(2)
                        Text(entry.author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let date = entry.formattedDate {
                            Text(date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    guard let parts = await playerVM.resolveItemParts(identifier: entry.id),
                          !parts.isEmpty else { return }
                    let ordered = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
                    await playerVM.playAlbumTracks(ordered, title: entry.displayName)
                }
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 48)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Audiobooks: \(entry.displayName) by \(entry.author)")
        .accessibilityHint("Tap left for details, tap right to play")
    }

    // MARK: - Audiobook Thumbnail

    private struct AudioBookThumb: View {
        let entry: AudiobookEntry

        var body: some View {
            AsyncImage(url: entry.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    if let cat = entry.categoryImageName {
                        Image(cat).resizable().scaledToFill()
                    } else {
                        Image("audiobooks").resizable().scaledToFill()
                    }
                @unknown default:
                    Image("audiobooks").resizable().scaledToFill()
                }
            }
        }
    }

    // MARK: - Category Card

    private func categoryCard(title: String, imageName: String?, route: HomeRoute) -> some View {
        NavigationLink(value: route) {
            ZStack {
                if let img = imageName {
                    Image(img)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    ChannelCategoryStyle.gradient(for: title)
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack {
                    Spacer()
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) category")
        .accessibilityHint("Opens \(title) browser")
        .buttonStyle(.plain)
    }

    private func iconCard(title: String, icon: String, color: Color, route: HomeRoute) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(.white.opacity(0.2)))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(color.gradient)
                    .shadow(color: color.opacity(0.4), radius: 8, y: 4)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)")
        .accessibilityHint("Opens \(title)")
        .buttonStyle(.plain)
    }

    // MARK: - Channel Category Sub-views

    @ViewBuilder
    private func channelCategoryView(for category: String) -> some View {
        if category == "Curated" || category == "Curated Books" {
            CuratedChannelsGrid(category: category, onSelectChannel: { channel in
                Task { await playerVM.load(channel: channel) }
                showPlayer = true
            })
            .environmentObject(playerVM)
            .environmentObject(playlistVM)
        } else {
            ChannelGridSubView(category: category,
                               channels: channels(in: category),
                               onSelectChannel: { channel in
                Task { await playerVM.load(channel: channel) }
                showPlayer = true
            })
        }
    }

    private var playlistsSubView: some View {
        PlaylistGridSubView(
            dismissAll: { showPlayer = true },
            onSelectChannel: { ch in
                Task { await playerVM.load(channel: ch) }
                showPlayer = true
            }
        )
        .environmentObject(playlistVM)
        .environmentObject(playerVM)
        .environmentObject(offlineService)
    }

    @ObservedObject private var podcastStore = PodcastSubscriptionStore.shared

    private func channels(in category: String) -> [Channel] {
        var chs = Channel.defaults.filter { $0.category == category }
        if category == "Podcasts" {
            let subs = podcastStore.subscriptions.map { podcastStore.channel(from: $0) }
            let subNames = Set(subs.map { $0.name.lowercased() })
            chs = chs.filter { !subNames.contains($0.name.lowercased()) }
            chs += subs
        }
        return chs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Inline Search Results

    @ViewBuilder
    private var searchResultsContent: some View {
        if searchVM.isSearching {
            VStack(spacing: 12) {
                Spacer().frame(height: 40)
                ProgressView()
                Text("Searching…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else if searchVM.showNoResults {
            ContentUnavailableView.search(text: searchText)
                .padding(.top, 80)
        } else if !searchVM.results.isEmpty {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Results").font(.headline).padding(.horizontal, 16).padding(.top, 8)
                ForEach(searchVM.displayedResults) { group in
                    Button {
                        Task {
                            await playerVM.playSearchResult(group)
                            showPlayer = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: resultIcon(group))
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title).font(.body).lineLimit(2)
                                Text(group.creator).font(.caption)
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .task { searchVM.loadItemInfo(group) }
                    Divider().padding(.leading, 56)
                }
            }
        }
    }

    private func resultIcon(_ group: SearchViewModel.ResultGroup) -> String {
        switch searchVM.itemKinds[group.id] {
        case .book:  return "book.closed.fill"
        case .album: return "square.stack.fill"
        case .track, nil:
            let c = (group.collection ?? "").lowercased()
            let bookish = ["librivox", "audiobook", "audio_books", "audio_bookspoetry"]
                .contains { c.contains($0) }
            return bookish ? "doc.text" : "music.note"
        }
    }

    // MARK: - Mini-player

    @ViewBuilder
    private var miniPlayer: some View {
        if let track = playerVM.currentTrack {
            Button {
                showPlayer = true
            } label: {
                HStack(spacing: 12) {
                    ArtworkThumbnail(track: track, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if reduceTransparency {
                        Color(.secondarySystemBackground)
                    } else {
                        Rectangle().fill(.thinMaterial)
                    }
                }
                .overlay(Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(.separator),
                         alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Mini player: \(track.title) by \(track.artist), \(playerVM.isPlaying ? "playing" : "paused")")
            .accessibilityHint("Opens the full player screen")
        }
    }
}

// MARK: - Channel Grid Sub-View

struct ChannelGridSubView: View {
    let category: String
    let channels: [Channel]
    let onSelectChannel: (Channel) -> Void

    @ObservedObject private var podcastStore = PodcastSubscriptionStore.shared
    @State private var showAddPodcast = false

    private var isPodcastsCategory: Bool { category == "Podcasts" }

    private var allChannels: [Channel] { channels }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(allChannels) { channel in
                    channelCard(channel)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPodcastsCategory {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddPodcast = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .accessibilityLabel("Add podcast feed")
                }
            }
        }
        .sheet(isPresented: $showAddPodcast) {
            PodcastAddView(initialMode: .url)
        }
    }

    /// For user-added podcast channels (id = "podcast-{uuid}"), the asset catalog
    /// image is named after the built-in channel's id. Resolve via name match.
    private func channelAssetName(for channel: Channel) -> String {
        if UIImage(named: channel.id) != nil { return channel.id }
        if channel.id.hasPrefix("podcast-"),
           let builtIn = Channel.defaults.first(where: {
               $0.name == channel.name && $0.category == "Podcasts" && !$0.id.hasPrefix("podcast-")
           }),
           UIImage(named: builtIn.id) != nil {
            return builtIn.id
        }
        return channel.id
    }

    @ViewBuilder
    private func channelCard(_ channel: Channel) -> some View {
        let isSubscribed = channel.id.hasPrefix("podcast-")

        Button {
            onSelectChannel(channel)
        } label: {
            ZStack {
                channelImageBackground(channel)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                if category != "Podcasts" {
                    VStack(alignment: .leading, spacing: 2) {
                        Spacer()
                        Group {
                            Text(channel.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            if let summary = channel.summary {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Plays this channel")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(channel.name)
        .contextMenu {
            NavigationLink(value: HomeRoute.channelInfo(channel)) {
                Label("Channel Info", systemImage: "info.circle")
            }
            if isSubscribed {
                Button(role: .destructive) {
                    if let sub = podcastStore.subscriptions.first(where: {
                        "podcast-\($0.id)" == channel.id
                    }) {
                        Task { await podcastStore.remove(sub) }
                    }
                } label: {
                    Label("Unsubscribe", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func channelImageBackground(_ channel: Channel) -> some View {
        let assetName = channelAssetName(for: channel)
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .clipped()
        } else if let imageURL = channel.imageURL, let url = URL(string: imageURL) {
            if url.isFileURL, let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage.squareScaled(to: CGSize(width: 300, height: 300)))
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill().clipped()
                    case .failure, .empty:
                        ChannelCategoryStyle.gradient(for: category)
                    @unknown default:
                        ChannelCategoryStyle.gradient(for: category)
                    }
                }
            }
        } else {
            ChannelCategoryStyle.gradient(for: category)
        }
    }
}

// MARK: - Curated Channels Grid

struct CuratedChannelsGrid: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @StateObject private var store = CustomChannelsStore.shared

    @State private var showNewChannel = false
    @State private var showCurateChannel: ChannelMeta?
    @State private var deleteConfirmChannel: ChannelMeta?
    @State private var resetConfirmChannel: ChannelMeta?
    @State private var editingChannel: ChannelMeta?
    @State private var renameText = ""
    @State private var curationRefreshID = UUID()

    var category: String = "Curated"
    let onSelectChannel: (Channel) -> Void

    private var filteredChannels: [ChannelMeta] {
        let all = store.orderedChannels()
        if category == "Curated Books" {
            let bookIDs = Set(Channel.defaults.filter { $0.category == "Curated Books" }.map(\.id))
            return all.filter { bookIDs.contains($0.id) }
        }
        let bookIDs = Set(Channel.defaults.filter { $0.category == "Curated Books" }.map(\.id))
        return all.filter { !bookIDs.contains($0.id) }
    }

    var body: some View {
        let orderedChannels = filteredChannels
        let runtimeChannels = Dictionary(uniqueKeysWithValues:
            orderedChannels.map { ($0.id, store.runtimeChannel(from: $0)) })

        ScrollView {
            if orderedChannels.isEmpty {
                ContentUnavailableView(
                    "No Curated Channels",
                    systemImage: "star.slash",
                    description: Text("Tap + to create a curated channel, or import one from a friend."))
                .padding(.top, 80)
            } else {
                if category == "Curated" {
                    CuratedDiscoveryHeader(label: "Curated Discovery", filterCategory: "Curated")
                        .id(curationRefreshID)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                if category == "Curated Books" {
                    CuratedDiscoveryHeader(label: "Curated Book", filterCategory: "Curated Books")
                        .id(curationRefreshID)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(orderedChannels, id: \.id) { meta in
                        let ch = runtimeChannels[meta.id]
                        let approvedCount = LiveCurationStore.shared.pool(for: meta.id).count
                        curatedChannelCard(meta, channel: ch, approvedCount: approvedCount)
                            .contextMenu {
                                Button {
                                    showCurateChannel = meta
                                } label: {
                                    Label("Curate", systemImage: "checklist")
                                }
                                Button {
                                    editingChannel = meta
                                    renameText = meta.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button {
                                    _ = store.duplicateChannel(chId: meta.id)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                ShareLink(item: store.exportURL(for: meta.id)) {
                                    Label("Export…", systemImage: "square.and.arrow.up")
                                }
                                if meta.isShippedDefault {
                                    Divider()
                                    Button {
                                        resetConfirmChannel = meta
                                    } label: {
                                        Label("Restore Factory Defaults", systemImage: "arrow.counterclockwise")
                                    }
                                }
                                Divider()
                                Button(role: .destructive) {
                                    deleteConfirmChannel = meta
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await LiveCurationStore.shared.reload(from: playerVM.db)
            curationRefreshID = UUID()
        }
        .navigationTitle(category == "Curated" ? "Curated Music" : "Curated Books")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewChannel = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New curated channel")
            }
        }
        .sheet(isPresented: $showNewChannel) {
            NewChannelSheet(onCreated: { meta in
                showNewChannel = false
                showCurateChannel = meta
            })
            .environmentObject(playerVM)
        }
        .onAppear {
            Task {
                await LiveCurationStore.shared.reload(from: playerVM.db)
            }
        }
        .sheet(item: $showCurateChannel) { meta in
            CuratorChannelEditView(channelMeta: meta, onDismiss: { showCurateChannel = nil })
        }
        .alert("Delete \"\(deleteConfirmChannel?.name ?? "")\"?", isPresented: Binding(
            get: { deleteConfirmChannel != nil },
            set: { if !$0 { deleteConfirmChannel = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let meta = deleteConfirmChannel {
                    store.deleteChannel(chId: meta.id)
                }
            }
            Button("Cancel", role: .cancel) { deleteConfirmChannel = nil }
        } message: {
            Text("This removes the channel from the list. Shipped defaults can be restored from Settings. Custom channels are permanently deleted.")
        }
        .alert("Restore \"\(resetConfirmChannel?.name ?? "")\"?", isPresented: Binding(
            get: { resetConfirmChannel != nil },
            set: { if !$0 { resetConfirmChannel = nil } }
        )) {
            Button("Restore", role: .destructive) {
                guard let meta = resetConfirmChannel else { return }
                Task {
                    await store.resetChannelToDefault(chId: meta.id, db: playerVM.db)
                }
            }
            Button("Cancel", role: .cancel) { resetConfirmChannel = nil }
        } message: {
            Text("This clears all your curation verdicts and restores the original list of approved tracks for this channel.")
        }
        .alert("Rename Channel", isPresented: Binding(
            get: { editingChannel != nil },
            set: { if !$0 { editingChannel = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let meta = editingChannel {
                    store.renameChannel(chId: meta.id, newName: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func curatedChannelCard(_ meta: ChannelMeta, channel: Channel?, approvedCount: Int) -> some View {
        Button {
            let ch = channel ?? store.runtimeChannel(from: meta)
            onSelectChannel(ch)
        } label: {
            ZStack {
                curatedChannelBackground(channel)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    Spacer()
                    Text(meta.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Plays this channel")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meta.name)" + (approvedCount > 0 ? ", \(approvedCount) tracks" : ""))
    }

    @ViewBuilder
    private func curatedChannelBackground(_ channel: Channel?) -> some View {
        if let ch = channel, UIImage(named: ch.id) != nil {
            Image(ch.id)
                .resizable()
                .scaledToFill()
                .clipped()
        } else if let ch = channel, let imageURL = ch.imageURL, let url = URL(string: imageURL) {
            if url.isFileURL, let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage.squareScaled(to: CGSize(width: 300, height: 300)))
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill().clipped()
                    case .failure, .empty:
                        ChannelCategoryStyle.gradient(for: "Curated")
                    @unknown default:
                        ChannelCategoryStyle.gradient(for: "Curated")
                    }
                }
            }
        } else {
            ChannelCategoryStyle.gradient(for: "Curated")
        }
    }
}

// MARK: - Playlists Grid Sub-View

struct PlaylistGridSubView: View {
    let dismissAll: () -> Void
    let onSelectChannel: (Channel) -> Void

    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService

    @State private var showCreate = false
    @State private var newName = ""

    private var musicForYou: Channel? {
        Channel.defaults.first { $0.id == "music-for-you" }
    }
    private var booksForYou: Channel? {
        Channel.defaults.first { $0.id == "books-for-you" }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                // For You section
                NavigationLink(value: HomeRoute.recentlyPlayed) {
                    sectionCardContent(title: "Recently Played", icon: "clock.arrow.circlepath", imageName: "recently-played")
                }
                .buttonStyle(.plain)
                if let m = musicForYou {
                    SectionCard(title: m.name, icon: "sparkles", imageName: "music-for-you") {
                        onSelectChannel(m)
                    }
                }
                if let b = booksForYou {
                    SectionCard(title: b.name, icon: "sparkles", imageName: "books-for-you") {
                        onSelectChannel(b)
                    }
                }

                // User playlists
                ForEach(playlistVM.playlists) { playlist in
                    playlistCard(playlist)
                }
            }
            .padding(16)

            if playlistVM.playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Add tracks to a playlist from Track Info or search to get started."))
                .padding(.top, 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Playlist")
            }
        }
        .alert("New Playlist", isPresented: $showCreate) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                newName = ""
                guard !name.isEmpty else { return }
                Task {
                    _ = await playlistVM.createPlaylist(name: name)
                    await playlistVM.loadPlaylists()
                }
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .task { await playlistVM.loadPlaylists() }
    }

    private func sectionCardContent(title: String, icon: String, imageName: String? = nil) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let img = imageName {
                Image(img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                ChannelCategoryStyle.gradient(for: "For You")
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    @ViewBuilder
    private func playlistCard(_ playlist: Playlist) -> some View {
        PlaylistGridCard(playlist: playlist, playlistVM: playlistVM, dismissAll: dismissAll, onSelectChannel: onSelectChannel)
    }
}

// MARK: - Individual playlist card (loads its own track data)

struct PlaylistGridCard: View {
    let playlist: Playlist
    @ObservedObject var playlistVM: PlaylistViewModel
    let dismissAll: () -> Void
    let onSelectChannel: (Channel) -> Void

    @State private var cardImage: UIImage?
    @State private var imageLoaded = false

    static var playlistImagesDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playlist-images")
    }

    var body: some View {
        NavigationLink(value: HomeRoute.playlist(playlist)) {
            ZStack {
                if playlist.isFavorites {
                    Image("favorites")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else if let img = cardImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    Image("playlists")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text(playlist.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.name), \(playlistVM.trackCount(for: playlist)) tracks"
            + (playlistVM.downloadedPlaylistIDs.contains(playlist.id) ? ", available offline" : ""))
        .accessibilityHint("Opens this playlist")
        .task {
            let customURL = Self.playlistImagesDir.appendingPathComponent("\(playlist.id).png")
            if FileManager.default.fileExists(atPath: customURL.path),
               let data = try? Data(contentsOf: customURL),
               let img = UIImage(data: data) {
                cardImage = img.squareScaled(to: CGSize(width: 300, height: 300))
                imageLoaded = true
                return
            }
            let tracks = await playlistVM.db.fetchTracks(forPlaylist: playlist.id)
            if let first = tracks.first,
               let art = await ArtworkService.shared.artwork(for: first) {
                cardImage = art.squareScaled(to: CGSize(width: 300, height: 300))
            }
            imageLoaded = true
        }
    }
}

// MARK: - Section Card (for "For You")

private struct SectionCard: View {
    let title: String
    let icon: String
    let imageName: String?
    let action: () -> Void

    init(title: String, icon: String, imageName: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.imageName = imageName
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                if let img = imageName {
                    Image(img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    ChannelCategoryStyle.gradient(for: "For You")
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Curated Discovery Header

struct CuratedDiscoveryHeader: View {
    let label: String
    let filterCategory: String

    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel

    @State private var track: Track?
    @State private var channelName: String?
    @State private var showDetail = false

    var body: some View {
        Group {
            if let t = track, let ch = channelName {
                curatedCard(t, channelName: ch)
            } else {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Placeholder title").font(.headline).lineLimit(2)
                        Text("Placeholder subtitle").font(.subheadline).lineLimit(1)
                        Text("Placeholder date").font(.caption)
                        ProgressView().padding(.top, 2)
                    }
                    .redacted(reason: .placeholder)
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
        .task {
            await LiveCurationStore.shared.reload(from: playerVM.db)
            let (t, ch) = await pickRandomTrack()
            track = t
            channelName = ch
        }
        .sheet(isPresented: $showDetail) {
            if let t = track, let ch = channelName {
                LiveMusicDetailView(entry: LiveMusicEntry(
                    id: t.parentIdentifier ?? t.id,
                    creator: t.artist, title: t.title, venue: ch,
                    coverage: nil, date: nil, year: nil,
                    downloads: 0, dateString: "", description: nil
                ))
                .environmentObject(playerVM)
                .environmentObject(playlistVM)
            }
        }
    }

    private func pickRandomTrack() async -> (Track?, String?) {
        let ids = Set(Channel.defaults
            .filter { $0.category == filterCategory }
            .map(\.id))
        let metas = CustomChannelsStore.shared.orderedChannels()
            .filter { ids.contains($0.id) }
        guard let channel = metas.randomElement() else { return (nil, nil) }
        let pool = LiveCurationStore.shared.pool(for: channel.id)
        let candidates = filterCategory == "Curated Books"
            ? pool.filter { $0.parentIdentifier != nil }
            : pool
        let source = candidates.isEmpty ? pool : candidates
        guard let t = source.randomElement() else { return (nil, nil) }
        return (t, channel.name)
    }

    private func curatedCard(_ track: Track, channelName: String) -> some View {
        let itemId = track.parentIdentifier ?? track.id
        return HStack(spacing: 0) {
            Button { showDetail = true } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: "https://archive.org/services/img/\(itemId)")) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Image(systemName: "music.note")
                                .font(.largeTitle).foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(ChannelCategoryStyle.gradient(for: "Curated"))
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(track.title)
                            .font(.headline).lineLimit(2)
                        Text(channelName)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        if !track.artist.isEmpty {
                            Text(track.artist)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            Button {
                Task {
                    let parts = await playerVM.resolveItemParts(identifier: itemId)
                    guard let p = parts, !p.isEmpty else { return }
                    let ordered = p.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
                    await playerVM.playAlbumTracks(ordered, title: track.title)
                }
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title).foregroundStyle(.blue).frame(width: 48)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
