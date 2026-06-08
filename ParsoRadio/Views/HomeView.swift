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

    // Session restore
    @State private var pendingChannel: Channel = {
        let raw = UserDefaults.standard.string(forKey: "lastChannelId") ?? "guitar-classical"
        let lastId = PlayerViewModel.migratedChannelId(raw) ?? raw
        return Channel.defaults.first { $0.id == lastId } ?? Channel.defaults[0]
    }()

    private static let categoryOrder = [
        "Curated", "Ambient", "Podcasts", "Audiobooks", "Lectures"
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
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lorewave")
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
            NowPlayingScreen(dismiss: { showPlayer = false })
                .environmentObject(playerVM)
                .environmentObject(playlistVM)
                .environmentObject(offlineService)
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

    private var homeGrid: some View {
        VStack(spacing: 0) {
            // Supporter badge for active subscribers
            if contributionStore.isSupporter, contributionStore.hasActiveSubscription {
                HStack {
                    Spacer()
                    let imageName: String = {
                        switch contributionStore.subscriptionTier {
                        case .yearly:  return "emperor_1024"
                        case .monthly: return "beethoven_1024"
                        case .none:    return ""
                        }
                    }()
                    if !imageName.isEmpty, let uiImage = UIImage(named: imageName) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                            .onTapGesture { showContributionSupport = true }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Categories grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                categoryCard(title: "Playlists", imageName: "playlists", route: HomeRoute.playlists)

                ForEach(Self.orderedCategories(), id: \.self) { category in
                    categoryCard(title: category, imageName: category.lowercased(), route: HomeRoute.channelCategory(category))
                }

                iconCard(title: "Settings", icon: "gearshape",
                         color: Color(red: 0.35, green: 0.35, blue: 0.40),
                         route: HomeRoute.settings)

                iconCard(title: "About", icon: "info.circle",
                         color: Color(red: 0.25, green: 0.30, blue: 0.45),
                         route: HomeRoute.about)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Category Card

    private func categoryCard(title: String, imageName: String?, route: HomeRoute) -> some View {
        NavigationLink(value: route) {
            ZStack(alignment: .bottomLeading) {
                if let img = imageName {
                    Image(img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ChannelCategoryStyle.gradient(for: title)
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
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
        if category == "Curated" {
            CuratedChannelsGrid(onSelectChannel: { channel in
                Task { await playerVM.load(channel: channel) }
                showPlayer = true
            })
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

    @ViewBuilder
    private func channelCard(_ channel: Channel) -> some View {
        let isSubscribed = channel.id.hasPrefix("podcast-")

        VStack(spacing: 0) {
            Button {
                onSelectChannel(channel)
            } label: {
                VStack(spacing: 10) {
                    channelImage(channel)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(spacing: 2) {
                        Text(channel.name)
                            .font(.subheadline).fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        if let summary = channel.summary {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Plays this channel")
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
    }

    @ViewBuilder
    private func channelImage(_ channel: Channel) -> some View {
        if let imageURL = channel.imageURL, let url = URL(string: imageURL) {
            if url.isFileURL, let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        fallbackIcon(channel)
                    case .empty:
                        ProgressView().scaleEffect(0.6)
                    @unknown default:
                        fallbackIcon(channel)
                    }
                }
            }
        } else {
            fallbackIcon(channel)
        }
    }

    @ViewBuilder
    private func fallbackIcon(_ channel: Channel) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(ChannelCategoryStyle.gradient(for: category))
            Image(systemName: channel.icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Curated Channels Grid

struct CuratedChannelsGrid: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @StateObject private var store = CustomChannelsStore.shared

    @State private var showNewChannel = false
    @State private var showCurateChannel: ChannelMeta?
    @State private var deleteConfirmChannel: ChannelMeta?
    @State private var editingChannel: ChannelMeta?
    @State private var renameText = ""

    let onSelectChannel: (Channel) -> Void

    var body: some View {
        let orderedChannels = store.orderedChannels()
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
        .navigationTitle("Curated")
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
        .task {
            await LiveCurationStore.shared.reload(from: playerVM.db)
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
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(ChannelCategoryStyle.gradient(for: "Curated"))
                        .frame(width: 64, height: 64)
                    Image(systemName: meta.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 2) {
                    Text(meta.name)
                        .font(.subheadline).fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if approvedCount > 0 {
                        Text("\(approvedCount) tracks")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Plays this channel")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meta.name)" + (approvedCount > 0 ? ", \(approvedCount) tracks" : ""))
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
                    sectionCardContent(title: "Recently Played", icon: "clock.arrow.circlepath")
                }
                .buttonStyle(.plain)
                if let m = musicForYou {
                    SectionCard(title: m.name, icon: "sparkles") {
                        onSelectChannel(m)
                    }
                }
                if let b = booksForYou {
                    SectionCard(title: b.name, icon: "sparkles") {
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

    private func sectionCardContent(title: String, icon: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(BrandGradient.linear)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.subheadline).fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private func playlistCard(_ playlist: Playlist) -> some View {
        NavigationLink(value: HomeRoute.playlist(playlist)) {
            VStack(spacing: 10) {
                playlistThumbnail(playlist)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        if playlist.isFavorites {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.caption2)
                        }
                        Text(playlist.name)
                            .font(.subheadline).fontWeight(.medium)
                            .lineLimit(2)
                    }
                    HStack(spacing: 4) {
                        if playlistVM.downloadedPlaylistIDs.contains(playlist.id) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        Text("\(playlistVM.trackCount(for: playlist)) tracks")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.name), \(playlistVM.trackCount(for: playlist)) tracks"
            + (playlistVM.downloadedPlaylistIDs.contains(playlist.id) ? ", available offline" : ""))
        .accessibilityHint("Opens this playlist")
    }

    @ViewBuilder
    private func playlistThumbnail(_ playlist: Playlist) -> some View {
        if let firstTrack = playlistVM.currentPlaylistTracks.first(where: { _ in true }), false {
            // Playlist tracks need to be loaded — for now use SF Symbol
            groupedIcon(icon: playlist.isFavorites ? "heart.fill" : "music.note.list",
                        color: playlist.isFavorites ? .red : Color(red: 0.18, green: 0.42, blue: 0.95))
        } else {
            groupedIcon(icon: playlist.isFavorites ? "heart.fill" : "music.note.list",
                        color: playlist.isFavorites ? .red : Color(red: 0.18, green: 0.42, blue: 0.95))
        }
    }

    @ViewBuilder
    private func groupedIcon(icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(color.gradient)
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Section Card (for "For You")

private struct SectionCard: View {
    let title: String
    let icon: String
    let action: () -> Void

    init(title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(BrandGradient.linear)
                        .frame(width: 64, height: 64)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
