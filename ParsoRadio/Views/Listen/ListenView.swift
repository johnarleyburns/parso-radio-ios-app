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
    @State private var showSupporterSheet = false

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
            .sheet(isPresented: $showAddCollection) {
                AddCollectionView()
            }
        }
    }

    @ViewBuilder
    private func channelsSection(for section: LibrarySection) -> some View {
        let subs = section.id == .podcast
            ? podcastStore.subscriptions.map { podcastStore.channel(from: $0) } : []
        let iaChannels = section.id == .music ? iaCollectionStore.channels : []
        let channels = (Channel.defaults
            .filter { $0.mediaKind == section.id && $0.category != "For You" }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            + iaChannels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            + subs
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
                        if let col = iaCollectionStore.collection(forChannelId: channel.id) {
                            Button(role: .destructive) {
                                iaCollectionStore.removeCollection(col)
                            } label: {
                                Label("Remove", systemImage: "trash")
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
