import SwiftUI

struct ChannelBrowseList: View {
    let kind: MediaKind

    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService

    @ObservedObject private var iaCollectionStore = IACollectionStore.shared
    @ObservedObject private var podcastStore = PodcastSubscriptionStore.shared

    @State private var nowPlayingChannel: Channel?
    @State private var showAddPodcast = false
    @State private var showAddCollection = false
    @State private var highlightChannelId: String?
    @State private var hiddenChannelIds: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "hiddenChannelIds") ?? [])
    }()

    private var section: LibrarySection { LibrarySection.section(for: kind) }
    private func select(_ channel: Channel) { nowPlayingChannel = channel }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                channelsSection
            }
            .listStyle(.insetGrouped)
            .onChange(of: iaCollectionStore.newlyAddedChannelId) { _, newId in
                guard kind == .music, let id = newId else { return }
                highlightChannelId = id
                withAnimation { proxy.scrollTo(id, anchor: .center) }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation(.easeOut(duration: 0.5)) { highlightChannelId = nil }
                    iaCollectionStore.newlyAddedChannelId = nil
                }
            }
        }
        .navigationTitle(section.label)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MenuRoute.self) { route in
            if case .channelInfo(let ch) = route { ChannelInfoView(channel: ch, playerVM: playerVM) }
        }
        .fullScreenCover(item: $nowPlayingChannel) { channel in
            NowPlayingSheet()
                .environmentObject(playerVM)
                .environmentObject(favorites)
                .environmentObject(playlistVM)
                .environmentObject(offlineService)
                .task { await playerVM.load(channel: channel, autoPlay: true) }
        }
        .sheet(isPresented: $showAddPodcast) { PodcastAddView(initialMode: .url) }
        .sheet(isPresented: $showAddCollection) { AddCollectionView() }
    }

    @ViewBuilder private var channelsSection: some View {
        let subs = kind == .podcast
            ? podcastStore.subscriptions.map { podcastStore.channel(from: $0) } : []
        let subscriptionChannelIDs = Set(subs.map(\.id))
        let iaChannels = kind == .music ? iaCollectionStore.channels : []
        let channels = (Channel.defaults
            .filter { $0.mediaKind == kind && $0.category != "For You" && !hiddenChannelIds.contains($0.id) }
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
                    .contextMenu { channelContextMenu(channel, subscriptionChannelIDs: subscriptionChannelIDs) }
                    .listRowBackground(
                        highlightChannelId == channel.id
                            ? Color.accentColor.opacity(0.15) : Color.clear
                    )
                    .animation(.easeInOut(duration: 0.5), value: highlightChannelId)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if subscriptionChannelIDs.contains(channel.id) {
                            Button(role: .destructive) {
                                Task {
                                    if let sub = podcastStore.subscriptions.first(where: { "podcast-\($0.id)" == channel.id }) {
                                        await podcastStore.remove(sub)
                                    }
                                }
                            } label: { Label("Unsubscribe", systemImage: "trash") }
                        } else if let col = iaCollectionStore.collection(forChannelId: channel.id) {
                            Button(role: .destructive) { iaCollectionStore.removeCollection(col) } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } else if Channel.defaults.contains(where: { $0.id == channel.id }) {
                            Button(role: .destructive) { hideChannel(channel.id) } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text(section.label)
                    Spacer()
                    if kind == .music {
                        Button { showAddCollection = true } label: {
                            Image(systemName: "plus.circle.fill").font(.body).foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel("Add collection")
                    }
                    if kind == .podcast {
                        Button { showAddPodcast = true } label: {
                            Image(systemName: "plus.circle.fill").font(.body).foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel("Add podcast")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func channelContextMenu(_ channel: Channel, subscriptionChannelIDs: Set<String> = []) -> some View {
        NavigationLink(value: MenuRoute.channelInfo(channel)) {
            Label("Channel Info", systemImage: "info.circle")
        }
        if subscriptionChannelIDs.contains(channel.id) {
            Button(role: .destructive) {
                Task {
                    if let sub = podcastStore.subscriptions.first(where: { "podcast-\($0.id)" == channel.id }) {
                        await podcastStore.remove(sub)
                    }
                }
            } label: { Label("Unsubscribe", systemImage: "trash") }
        }
    }

    private func hideChannel(_ id: String) {
        hiddenChannelIds.insert(id)
        UserDefaults.standard.set(Array(hiddenChannelIds), forKey: "hiddenChannelIds")
    }
}
