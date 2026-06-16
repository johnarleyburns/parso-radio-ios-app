import SwiftUI

struct ListenView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var deps: AppDependencies
    @State private var showSettings = false
    @State private var nowPlayingChannel: Channel?
    @State private var showAddPodcast = false
    @State private var showNewCuratedChannel = false
    @State private var curateMeta: ChannelMeta?
    @State private var selectedRecentTrack: Track?
    @State private var showSupporterSheet = false

    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore
    @AppStorage("supporterBadgeHidden") private var supporterBadgeHidden = false
    @ObservedObject private var customChannelStore = CustomChannelsStore.shared
    @ObservedObject private var podcastStore = PodcastSubscriptionStore.shared

    private func select(_ channel: Channel) { nowPlayingChannel = channel }

    var body: some View {
        NavigationStack {
            List {
                JumpBackInSection(playerVM: playerVM) { track in
                    selectedRecentTrack = track
                }

                LiveMusicSection(onSelect: select, playerVM: playerVM, deps: deps)

                ForYouSection(onSelect: select)

                ForEach(LibrarySection.ordered) { section in
                    channelsSection(for: section)
                }
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
            .sheet(isPresented: $showNewCuratedChannel) {
                NewChannelSheet(onCreated: { meta in
                    showNewCuratedChannel = false
                    curateMeta = meta
                })
                .environmentObject(playerVM)
            }
            .sheet(item: $curateMeta) { meta in
                CuratorChannelEditView(
                    channelMeta: meta,
                    playerVM: playerVM,
                    onDismiss: { curateMeta = nil })
            }
        }
    }

    @ViewBuilder
    private func channelsSection(for section: LibrarySection) -> some View {
        let dedicated: Set<String> = ["For You"]
        let subs = section.id == .podcast
            ? podcastStore.subscriptions.map { podcastStore.channel(from: $0) } : []
        let channels = (Channel.defaults
            .filter { $0.mediaKind == section.id && !dedicated.contains($0.category) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) + subs
        if channels.isEmpty { EmptyView() }
        else {
            Section {
                ForEach(channels, id: \.id) { channel in
                    Button { select(channel) } label: {
                        HStack {
                            Label(channel.name, systemImage: channel.icon)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { channelContextMenu(channel) }
                    .swipeActions(edge: .trailing) {
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
                        }
                    }
                }
            } header: {
                HStack {
                    Text(section.label)
                    Spacer()
                    if section.id == .music {
                        Button { showNewCuratedChannel = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel("Add curated music channel")
                    }
                    if section.id == .audiobook {
                        Button { showNewCuratedChannel = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel("Add curated books channel")
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
        if let meta = customChannelStore.customChannels.first(where: { $0.id == channel.id }) {
            Button {
                curateMeta = meta
            } label: {
                Label("Curate", systemImage: "checklist")
            }
        }

        NavigationLink(value: MenuRoute.channelInfo(channel)) {
            Label("Channel Info", systemImage: "info.circle")
        }
    }
}

private struct ForYouSection: View {
    let onSelect: (Channel) -> Void

    var body: some View {
        let forYouChannels = Channel.defaults
            .filter { $0.category == "For You" && $0.id == "for-you" }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !forYouChannels.isEmpty {
            Section("Curated Based on Your Taste") {
                ForEach(forYouChannels, id: \.id) { channel in
                    Button { onSelect(channel) } label: {
                        Label(channel.name, systemImage: channel.icon)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LiveMusicSection: View {
    @ObservedObject private var store = LiveMusicOnThisDayStore.shared
    let onSelect: (Channel) -> Void
    let playerVM: PlayerViewModel
    let deps: AppDependencies
    var body: some View {
        Section("Live Music on This Day") {
            if store.isLoading {
                HStack(spacing: 12) {
                    Color(.systemGray5)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            ProgressView()
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Searching…")
                            .font(.subheadline.weight(.medium))
                        Text("Live Music Archive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(minHeight: 56)
            } else if let entry = store.entry {
                Button {
                    Task { await playLiveEntry(entry) }
                } label: {
                    HStack(spacing: 12) {
                        VerifiedThumb(url: entry.thumbnailURL, fallbackName: { "music.mic" })
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
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
                        }
                        Spacer()
                        Image(systemName: "play.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("No live recordings found for today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
    }

    private func playLiveEntry(_ entry: LiveMusicEntry) async {
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
