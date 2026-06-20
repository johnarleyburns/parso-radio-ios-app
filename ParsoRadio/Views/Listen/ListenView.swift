import SwiftUI

struct ListenView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var deps: AppDependencies
    @State private var showSettings = false
    @State private var nowPlayingChannel: Channel?
    @State private var showAddPodcast = false
    @State private var showAddCollection = false
    @State private var selectedRecentTrack: Track?
    @State private var selectedLiveEntry: LiveMusicEntry?
    @State private var showSupporterSheet = false
    @State private var hiddenChannelIds: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "hiddenChannelIds") ?? [])
    }()

    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore
    @AppStorage("supporterBadgeHidden") private var supporterBadgeHidden = false
    @ObservedObject private var iaCollectionStore = IACollectionStore.shared
    @ObservedObject private var podcastStore = PodcastSubscriptionStore.shared

    private func select(_ channel: Channel) { nowPlayingChannel = channel }

    var body: some View {
        NavigationStack {
            List {
                JumpBackInSection(playerVM: playerVM) { track in
                    selectedRecentTrack = track
                }

                LiveMusicSection(playerVM: playerVM, deps: deps) { entry in
                    selectedLiveEntry = entry
                }

                ForEach(LibrarySection.ordered) { section in
                    channelsSection(for: section)
                }

                Color.clear
                    .frame(height: 60)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Listen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if contributionStore.isSupporter && !supporterBadgeHidden {
                            Button {
                                showSupporterSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("SUPPORTER")
                                        .font(.caption2)
                                        .fontDesign(.rounded)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                    Image(systemName: "heart.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .accessibilityLabel("Supporter")
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .sheet(isPresented: $showSupporterSheet) {
                NavigationStack {
                    ContributionSupportView(store: contributionStore, showsDoneButton: true)
                }
            }
            .fullScreenCover(item: $nowPlayingChannel) { channel in
                NowPlayingSheet()
                    .environmentObject(playerVM)
                    .environmentObject(favorites)
                    .environmentObject(playlistVM)
                    .task { await playerVM.load(channel: channel, autoPlay: true) }
            }
            .fullScreenCover(item: $selectedRecentTrack) { track in
                NowPlayingSheet()
                    .environmentObject(playerVM)
                    .environmentObject(favorites)
                    .environmentObject(playlistVM)
                    .task { await playerVM.playRecentTrack(track) }
            }
            .sheet(isPresented: $showAddPodcast) {
                PodcastAddView(initialMode: .url)
            }
            .sheet(isPresented: $showAddCollection) {
                AddCollectionView()
            }
            .sheet(item: $selectedLiveEntry) { entry in
                LiveMusicDetailView(entry: entry)
                    .environmentObject(playerVM)
                    .environmentObject(playlistVM)
            }
        }
    }

    @ViewBuilder
    private func channelsSection(for section: LibrarySection) -> some View {
        let subs = section.id == .podcast
            ? podcastStore.subscriptions.map { podcastStore.channel(from: $0) } : []
        let iaChannels = section.id == .music ? iaCollectionStore.channels : []
        let channels = (Channel.defaults
            .filter { $0.mediaKind == section.id && $0.category != "For You" && !hiddenChannelIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            + iaChannels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            + subs
        if channels.isEmpty { EmptyView() }
        else {
            Section {
                ForEach(channels, id: \.id) { channel in
                    HStack {
                        Label(channel.name, systemImage: channel.icon)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { select(channel) }
                    .contextMenu { channelContextMenu(channel) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if podcastStore.subscriptions.contains(where: { $0.id == channel.id }) {
                            Button(role: .destructive) {
                                Task {
                                    if let sub = podcastStore.subscriptions.first(where: { $0.id == channel.id }) {
                                        await podcastStore.remove(sub)
                                    }
                                }
                            } label: {
                                Label("Unsubscribe", systemImage: "trash")
                            }
                        } else if let col = iaCollectionStore.collection(forChannelId: channel.id) {
                            Button(role: .destructive) {
                                iaCollectionStore.removeCollection(col)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } else if Channel.defaults.contains(where: { $0.id == channel.id }) {
                            Button(role: .destructive) {
                                hideChannel(channel.id)
                            } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text(section.label)
                    Spacer()
                    if section.id == .music {
                        Button { showAddCollection = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel("Add collection")
                    }
                    if section.id == .podcast {
                        Button { showAddPodcast = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel("Add podcast")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func channelContextMenu(_ channel: Channel) -> some View {
        NavigationLink(value: MenuRoute.channelInfo(channel)) {
            Label("Channel Info", systemImage: "info.circle")
        }
    }

    private func hideChannel(_ id: String) {
        hiddenChannelIds.insert(id)
        UserDefaults.standard.set(Array(hiddenChannelIds), forKey: "hiddenChannelIds")
    }
}

private struct JumpBackInSection: View {
    let playerVM: PlayerViewModel
    let onSelect: (Track) -> Void
    @State private var items: [Track] = []

    var body: some View {
        Group {
            if !items.isEmpty {
                Section("Jump Back In") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(items, id: \.id) { track in
                                Button { onSelect(track) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        AsyncImage(url: track.resolvedArtworkURL) { phase in
                                            if let img = phase.image { img.resizable().scaledToFill() }
                                            else { Color(.systemGray5).overlay(Image(systemName: "music.note")) }
                                        }
                                        .frame(width: 120, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        Text(track.title).font(.caption.weight(.medium)).lineLimit(1)
                                        Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(width: 120)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
                }
            }
        }
        .task { items = await playerVM.recentlyPlayedTracks(limit: 10) }
    }
}

private struct LiveMusicSection: View {
    @ObservedObject private var store = LiveMusicOnThisDayStore.shared
    let playerVM: PlayerViewModel
    let deps: AppDependencies
    let onDetail: (LiveMusicEntry) -> Void

    @State private var useFallbackImage = false

    var body: some View {
        Section {
            HStack(spacing: 0) {
                Button {
                    if let entry = store.entry { onDetail(entry) }
                } label: {
                    HStack(spacing: 12) {
                        liveMusicThumbnail

                        VStack(alignment: .leading, spacing: 3) {
                            if store.isLoading {
                                Text("Searching\u{2026}")
                                    .font(.subheadline.weight(.medium))
                                Text("Live Music Archive")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let entry = store.entry {
                                Text(entry.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                if let location = entry.locationSummary {
                                    Text(location)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if let date = entry.formattedDate {
                                    Text(date)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            } else {
                                Text("No live recordings found for today.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.entry == nil)

                if store.entry != nil {
                    Button {
                        Task { await playAll() }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play live recording")
                    .padding(.leading, 4)
                }
            }
            .frame(height: 72)
        } header: {
            Text("Live Music on This Day")
        }
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
    }

    @ViewBuilder
    private var liveMusicThumbnail: some View {
        Group {
            if store.isLoading {
                Color(.systemGray5)
                    .overlay { ProgressView() }
            } else if store.entry != nil && !useFallbackImage {
                AsyncImage(url: store.entry!.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .task { await verifyImageSize() }
                    case .failure, .empty:
                        Image("live-music-default").resizable().scaledToFill()
                            .onAppear { useFallbackImage = true }
                    @unknown default:
                        Image("live-music-default").resizable().scaledToFill()
                    }
                }
            } else if store.entry != nil {
                Image("live-music-default").resizable().scaledToFill()
            } else {
                Color(.systemGray5)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func verifyImageSize() async {
        guard let entry = store.entry else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: entry.thumbnailURL),
              data.count < 2048
        else { return }
        useFallbackImage = true
    }

    private func playAll() async {
        guard let entry = store.entry else { return }
        do {
            let tracks = try await deps.archiveService.fetchTracksForIdentifier(entry.id)
            guard !tracks.isEmpty else {
                playerVM.errorMessage = "This recording doesn't have any playable audio files — it may use unsupported formats like SHN."
                return
            }
            await playerVM.playAlbumTracks(tracks, title: entry.displayName)
        } catch {
            playerVM.errorMessage = "Couldn't load this recording. Try again later."
        }
    }
}
