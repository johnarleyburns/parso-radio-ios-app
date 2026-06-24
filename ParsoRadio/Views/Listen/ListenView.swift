import SwiftUI

struct ListenView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var deps: AppDependencies
    @State private var showSettings = false
    @State private var nowPlayingChannel: Channel?
    @State private var selectedRecentTrack: Track?
    @State private var selectedLiveEntry: LiveMusicEntry?
    @State private var showSupporterSheet = false

    @ObservedObject private var contributionStore = ParsoMusicApp.sharedContributionStore
    @AppStorage("supporterBadgeHidden") private var supporterBadgeHidden = false

    var body: some View {
        NavigationStack {
            List {
                HomeTopSection(playerVM: playerVM,
                               onSelectTrack: { selectedRecentTrack = $0 },
                               onPlayHero: { playHero() })

                MadeForYouSection()

                ExploreTypeRow()

                FeaturedTodaySection(nowPlayingChannel: $nowPlayingChannel)

                BookForYouSection(playerVM: playerVM, deps: deps)

                LiveMusicSection(playerVM: playerVM, deps: deps) { entry in
                    selectedLiveEntry = entry
                }

                Section {
                    NavigationLink {
                        List { ForEach(LibrarySection.ordered) { s in
                            NavigationLink { ChannelBrowseList(kind: s.id) } label: { Label(s.label, systemImage: s.icon) }
                        } }
                        .listStyle(.insetGrouped)
                        .navigationTitle("Browse")
                    } label: {
                        Label("Browse all collections", systemImage: "square.grid.2x2")
                    }
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
            .sheet(item: $selectedLiveEntry) { entry in
                LiveMusicDetailView(entry: entry)
                    .environmentObject(playerVM)
                    .environmentObject(playlistVM)
            }
        }
    }

    private func playHero() {
        let pool = Channel.defaults + IACollectionStore.shared.channels
        if let c = FeaturedPicker.hero(on: Date(), from: pool) { nowPlayingChannel = c }
    }
}

private struct LiveMusicSection: View {
    @ObservedObject private var store = LiveMusicOnThisDayStore.shared
    let playerVM: PlayerViewModel
    let deps: AppDependencies
    let onDetail: (LiveMusicEntry) -> Void

    @State private var useFallbackImage = false

    private var isLoaded: Bool {
        if case .loaded = store.state { return true }
        return false
    }

    private var currentEntry: LiveMusicEntry? {
        if case .loaded(let entry) = store.state { return entry }
        return nil
    }

    var body: some View {
        Section {
            HStack(spacing: 0) {
                Button {
                    if let entry = currentEntry { onDetail(entry) }
                } label: {
                    HStack(spacing: 12) {
                        liveMusicThumbnail

                        VStack(alignment: .leading, spacing: 3) {
                            switch store.state {
                            case .loading:
                                Text("Searching\u{2026}")
                                    .font(.subheadline.weight(.medium))
                                Text("Live Music Archive")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .loaded(let entry):
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
                            case .empty(let msg), .failed(let msg, _):
                                Text(msg)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            case .idle:
                                Text("Live Music Archive")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isLoaded)

                if isLoaded {
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
        .refreshable { await store.refreshFromPool() }
        .task { await store.loadIfNeeded() }
    }

    @ViewBuilder
    private var liveMusicThumbnail: some View {
        Group {
            switch store.state {
            case .loading:
                Color(.systemGray5)
                    .overlay { ProgressView() }
            case .loaded(let entry):
                if useFallbackImage {
                    Image("live-music-default").resizable().scaledToFill()
                } else {
                    AsyncImage(url: entry.thumbnailURL) { phase in
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
                }
            case .idle, .empty, .failed:
                Color(.systemGray5)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func verifyImageSize() async {
        guard let entry = currentEntry else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: entry.thumbnailURL),
              data.count < 2048
        else { return }
        useFallbackImage = true
    }

    private func playAll() async {
        guard let entry = currentEntry else { return }
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

private struct BookForYouSection: View {
    @ObservedObject private var store = BookForYouStore.shared
    let playerVM: PlayerViewModel
    let deps: AppDependencies

    @State private var useFallbackImage = false

    var body: some View {
        Section {
            HStack(spacing: 0) {
                Button {
                    Task { await playBook() }
                } label: {
                    HStack(spacing: 12) {
                        bookThumbnail

                        VStack(alignment: .leading, spacing: 3) {
                            if store.isLoading {
                                Text("Finding your book\u{2026}")
                                    .font(.subheadline.weight(.medium))
                                Text("LibriVox")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let entry = store.entry {
                                Text(entry.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                Text(entry.author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(entry.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            } else {
                                Text("No book available today. Check back tomorrow.")
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
                        Task { await playBook() }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play book")
                    .padding(.leading, 4)
                }
            }
            .frame(height: 72)
        } header: {
            Text("A Book Curated For You")
        }
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
    }

    @ViewBuilder
    private var bookThumbnail: some View {
        Group {
            if store.isLoading {
                Color(.systemGray5)
                    .overlay { ProgressView() }
            } else if store.entry != nil && !useFallbackImage {
                AsyncImage(url: store.entry!.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        Image("book-curated-default").resizable().scaledToFill()
                            .onAppear { useFallbackImage = true }
                    @unknown default:
                        Image("book-curated-default").resizable().scaledToFill()
                    }
                }
            } else if store.entry != nil {
                Image("book-curated-default").resizable().scaledToFill()
            } else {
                Color(.systemGray5)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func playBook() async {
        guard let entry = store.entry else { return }
        do {
            let tracks = try await deps.archiveService.fetchTracksForIdentifier(entry.identifier)
            guard !tracks.isEmpty else {
                playerVM.errorMessage = "This book doesn't have any playable audio files."
                return
            }
            await playerVM.playAlbumTracks(tracks, title: entry.title)
        } catch {
            playerVM.errorMessage = "Couldn't load this book. Try again later."
        }
    }
}
