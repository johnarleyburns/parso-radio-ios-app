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

    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore
    @AppStorage("supporterBadgeHidden") private var supporterBadgeHidden = false
    @ObservedObject private var customChannelStore = CustomChannelsStore.shared

    private func select(_ channel: Channel) { nowPlayingChannel = channel }

    var body: some View {
        NavigationStack {
            List {
                ForYouSection(onSelect: select)

                ForEach(LibrarySection.ordered) { section in
                    channelsSection(for: section)
                }

                LiveMusicSection(onSelect: select, playerVM: playerVM)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Listen")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Listen")
                            .font(.headline)
                        if contributionStore.isSupporter && !supporterBadgeHidden {
                            Image(systemName: "seal.fill")
                                .font(.headline)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .fullScreenCover(item: $nowPlayingChannel) { channel in
                NowPlayingSheet()
                    .environmentObject(playerVM)
                    .environmentObject(favorites)
                    .environmentObject(playlistVM)
                    .task { await playerVM.load(channel: channel) }
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
        let channels = Channel.defaults.filter {
            $0.mediaKind == section.id && !dedicated.contains($0.category)
        }
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
                }
            } header: {
                HStack {
                    Text(section.label)
                    Spacer()
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
        let forYouChannels = Channel.defaults.filter { $0.category == "For You" }
        if !forYouChannels.isEmpty {
            Section("For You") {
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
    let onSelect: (Channel) -> Void
    let playerVM: PlayerViewModel

    @State private var entry: LiveMusicEntry?
    @State private var isLoading = true

    var body: some View {
        Section("Live Music on This Day") {
            if isLoading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Searching the Live Music Archive...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let entry {
                Button {
                    Task { await playLiveEntry(entry) }
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: entry.thumbnailURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Color(.systemGray5)
                                    .overlay {
                                        Image(systemName: "music.mic")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                        }
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
        .task {
            isLoading = true
            let service = LiveMusicOnThisDayService()
            entry = await service.fetchDailyEntry()
            isLoading = false
        }
    }

    private func playLiveEntry(_ entry: LiveMusicEntry) async {
        let track = Track(
            id: entry.id,
            source: "internet_archive",
            title: entry.displayName,
            artist: entry.creator,
            duration: 0,
            streamURL: URL(string: "https://archive.org/download/\(entry.id)")!,
            downloadURL: nil,
            localFilePath: nil,
            license: .publicDomain,
            tags: [],
            qualityScore: 1.0,
            rawCreator: entry.creator,
            composer: nil,
            instruments: [],
            metadataConfidence: 1.0,
            addedDate: Date()
        )
        await playerVM.playSingleTrack(track)
    }
}
