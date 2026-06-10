import SwiftUI

// Pushed destinations within the Main Menu's navigation stack. Drilling in
// (and the wheel-MENU contextual push) means the standard back chevron returns
// to the menu list.
enum MenuRoute: Hashable {
    case playlist(Playlist)
    case channelInfo(Channel)
    case channelList(String)   // a category → its Channels screen
    case playlists             // the Playlists library screen
    case recentlyPlayed        // the Recently Played history screen
    case settings              // appearance + data management
}

struct MainMenuView: View {
    var initialRoute: MenuRoute? = nil
    let onSelectChannel: (Channel) -> Void
    let dismissAll: () -> Void          // close the whole menu (back to player)
    // Stable closure so CuratedChannelsListView identity doesn't change when
    // body recomputes from @Published currentPosition ticks.
    private let selectCuratedAndDismiss: (Channel) -> Void

    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var showAbout = false
    @State private var recentlyPlayed: [Track] = []
    @State private var path: [MenuRoute] = []
    // Inline search. searchActive (iOS 17 isPresented) is true the moment the
    // field is focused, so the menu sections hide immediately on focus. Search
    // runs only on submit (Return / Search key), not as you type.
    @StateObject private var searchVM = SearchViewModel()
    @State private var searchText = ""
    @State private var searchActive = false

    init(initialRoute: MenuRoute? = nil,
         onSelectChannel: @escaping (Channel) -> Void,
         dismissAll: @escaping () -> Void) {
        self.initialRoute = initialRoute
        self.onSelectChannel = onSelectChannel
        self.dismissAll = dismissAll
        self.selectCuratedAndDismiss = { channel in
            onSelectChannel(channel)
            dismissAll()
        }
        // Seed the path SYNCHRONOUSLY so the route is in place before first
        // render. (Pushing it later from an async .task let a quick Back tap
        // get overwritten when the await finished — the "bounces back into
        // Channel Info" bug.)
        //
        // Expand a deep-linked Channel Info / Playlist into its proper parent →
        // child hierarchy so the back chevron lands at the natural "level up"
        // (the category list, or the Playlists library) instead of jumping all
        // the way to the Main Menu root. Other routes (channelList, playlists,
        // recentlyPlayed, settings) already sit one level under the root.
        let expanded: [MenuRoute]
        switch initialRoute {
        case .channelInfo(let ch):
            expanded = [.channelList(ch.category), .channelInfo(ch)]
        case .playlist(let pl):
            expanded = [.playlists, .playlist(pl)]
        case .some(let r):
            expanded = [r]
        case .none:
            expanded = []
        }
        _path = State(initialValue: expanded)
    }

    // Fixed section order. Alphabetical WITHIN each.
    // NOTE: "For You" is INTENTIONALLY OMITTED here — Music for You and Books
    // for You are surfaced as auto-generated entries at the top of the Playlists
    // screen instead, alongside Recently Played, so the top-level menu stays
    // focused on real channel categories.
    private static let categoryOrder = [
        "Curated", "Ambient", "Podcasts", "Audiobooks", "Curated Books", "Lectures"
    ]

    static func orderedCategories() -> [String] {
        let present = Set(Channel.defaults.map(\.category))
        return categoryOrder.filter(present.contains)
    }

    @ObservedObject private var podcastStore = PodcastSubscriptionStore.shared

    private func channels(in category: String) -> [Channel] {
        var chs = Channel.defaults.filter { $0.category == category }
        if category == "Podcasts" {
            chs += podcastStore.subscriptions.map { podcastStore.channel(from: $0) }
        }
        return chs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if searchActive {
                    searchResultsContent
                } else {
                    menuContent
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Lorewave")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MenuRoute.self) { route in
                switch route {
                case .playlist(let pl):
                    PlaylistDetailView(playlist: pl, dismissAll: dismissAll)
                        .environmentObject(playlistVM)
                        .environmentObject(playerVM)
                        .environmentObject(offlineService)
                case .channelInfo(let ch):
                    ChannelInfoView(channel: ch)
                case .channelList(let category):
                    if category == "Curated" {
                        CuratedChannelsListView(
                            playerVM: playerVM,
                            onSelectChannel: selectCuratedAndDismiss)
                    } else {
                        ChannelListScreen(category: category,
                                          channels: channels(in: category),
                                          onSelect: { channel in onSelectChannel(channel) })
                    }
                case .playlists:
                    PlaylistsScreen(
                        dismissAll: dismissAll,
                        onSelectChannel: { ch in onSelectChannel(ch) }
                    )
                        .environmentObject(playlistVM)
                        .environmentObject(playerVM)
                        .environmentObject(offlineService)
                case .recentlyPlayed:
                    RecentlyPlayedScreen(dismissAll: dismissAll)
                        .environmentObject(playerVM)
                case .settings:
                    SettingsView()
                        .environmentObject(playerVM)
                        .environmentObject(playlistVM)
                        .environmentObject(offlineService)
                }
            }
            // Inline search per Apple HIG. isPresented hides the menu on focus;
            // results appear only after the user submits.
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .task {
                recentlyPlayed = await playerVM.recentlyPlayedTracks(limit: 30)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if playerVM.currentTrack != nil {
                miniPlayer
            }
        }
    }

    // MARK: - Menu content (drill-down library)

    @ViewBuilder
    private var menuContent: some View {
        // Library: simple drill-down rows (HIG) — tap pushes the matching
        // screen; the back chevron returns here.
        // Library: simple drill-down rows (HIG). "Recently Played" and the
        // For-You auto-feeds now live INSIDE Playlists, so the top-level Library
        // stays small. The Categories rows below follow.
        Section("Library") {
            NavigationLink(value: MenuRoute.playlists) {
                HStack {
                    Label("Playlists", systemImage: "music.note.list")
                    Spacer()
                    Text("\(playlistVM.playlists.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
                ForEach(Self.orderedCategories(), id: \.self) { category in
                    NavigationLink(value: MenuRoute.channelList(category)) {
                        HStack {
                            Label(category == "Curated" ? "Curated Music" : category, systemImage: Self.categoryIcon(category))
                        Spacer()
                        Text("\(channels(in: category).count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section {
            NavigationLink(value: MenuRoute.settings) {
                Label("Settings", systemImage: "gearshape")
                    .font(.body).padding(.vertical, 2)
            }
            Button {
                showAbout = true
            } label: {
                Label("About", systemImage: "info.circle")
                    .font(.body).padding(.vertical, 2)
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Inline search results

    @ViewBuilder
    private var searchResultsContent: some View {
        if searchVM.isSearching {
            // Mirror the player's "Loading…" affordance while a search runs.
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching…").foregroundStyle(.secondary)
                }
            }
        } else if searchVM.showNoResults {
            // Only AFTER a search returned nothing — never before searching.
            Section { ContentUnavailableView.search(text: searchText) }
        } else if !searchVM.results.isEmpty {
            Section("Results") {
                ForEach(searchVM.displayedResults) { group in
                    Button {
                        Task {
                            await playerVM.playSearchResult(group)
                            dismissAll()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: resultIcon(group))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title).font(.body).lineLimit(2)
                                Text(group.creator).font(.caption)
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .task { searchVM.loadItemInfo(group) }   // resolves kind → icon + ranking
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Plays this result")
                }
            }
        }
        // else: search field focused but nothing searched yet → show nothing.
    }

    // Leading icon by item kind: whole album, whole book, a single audiobook
    // chapter, or a single music track.
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

    // SF Symbol per menu category.
    static func categoryIcon(_ category: String) -> String {
        switch category {
        case "For You":      return "sparkles"
        case "Curated":      return "star"
        case "Curated Books": return "books.vertical"
        case "Ambient":      return "leaf"
        case "Podcasts":    return "newspaper"
        case "Contemporary": return "guitars"
        case "Audiobooks":   return "book"
        case "Lectures":     return "graduationcap"
        default:             return "music.note.list"
        }
    }

    // MARK: - Mini-player (sticky bottom bar)

    @ViewBuilder
    private var miniPlayer: some View {
        if let track = playerVM.currentTrack {
            HStack(spacing: 12) {
                ArtworkThumbnail(track: track, size: 40)
                    .accessibilityHidden(true)
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
            // Honor Reduce Transparency with an opaque fallback (HIG).
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
            .onTapGesture { dismissAll() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Mini player: \(track.title) by \(track.artist), \(playerVM.isPlaying ? "playing" : "paused")")
            .accessibilityHint("Tap to return to the player screen")
        }
    }
}
