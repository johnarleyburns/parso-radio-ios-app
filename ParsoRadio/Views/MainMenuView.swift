import SwiftUI

// Pushed destinations within the Main Menu's navigation stack. Reaching a
// playlist / channel-info this way means the standard back chevron returns to
// the menu list — the "back to main menu" the wheel-MENU navigation needs.
enum MenuRoute: Hashable {
    case playlist(Playlist)
    case channelInfo(Channel)
}

struct MainMenuView: View {
    var initialRoute: MenuRoute? = nil
    let onSelectChannel: (Channel) -> Void
    let dismissAll: () -> Void          // close the whole menu (back to player)

    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @Environment(\.dismiss) private var dismiss

    @State private var showAbout = false
    @State private var recentlyPlayed: [Track] = []
    @State private var path: [MenuRoute] = []
    // Section IDs currently expanded. Empty = all collapsed (the default).
    @State private var expanded: Set<String> = []
    @State private var editMode: EditMode = .inactive
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
        // Seed the path SYNCHRONOUSLY so the route is in place before first
        // render. (Pushing it later from an async .task let a quick Back tap
        // get overwritten when the await finished — the "bounces back into
        // Channel Info" bug.)
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
    }

    // Fixed section order. Alphabetical WITHIN each.
    private static let categoryOrder = [
        "Curated", "Ambient", "News", "Contemporary", "Audiobooks", "Lectures"
    ]

    static func orderedCategories() -> [String] {
        let present = Set(Channel.defaults.map(\.category))
        return categoryOrder.filter(present.contains)
    }

    private func channels(in category: String) -> [Channel] {
        Channel.defaults
            .filter { $0.category == category }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // A playlist row ALWAYS opens the playlist detail (never starts playing),
    // pushed via the navigation path so the back chevron returns here.
    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        NavigationLink(value: MenuRoute.playlist(playlist)) {
            HStack {
                Label(playlist.name,
                      systemImage: playlist.isFavorites ? "heart.fill" : "music.note.list")
                Spacer()
                Text("\(playlistVM.trackCount(for: playlist))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.name), \(playlistVM.trackCount(for: playlist)) tracks")
        .accessibilityHint("Opens this playlist")
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
            // Collapsed sections shouldn't leave big gaps between headers.
            .listSectionSpacing(.compact)
            .environment(\.editMode, $editMode)
            .navigationTitle("Parso Music")
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
            .safeAreaInset(edge: .bottom) {
                if playerVM.currentTrack != nil {
                    miniPlayer
                }
            }
            .task {
                recentlyPlayed = await playerVM.recentlyPlayedTracks(limit: 30)
            }
        }
    }

    // MARK: - Menu content (recents + playlists + categories + about)

    @ViewBuilder
    private var menuContent: some View {
        recentlyPlayedSection            // always shown (placeholder when empty)

        let favorites = playlistVM.playlists.filter { $0.isFavorites }
        let others    = playlistVM.playlists.filter { !$0.isFavorites }
        if !playlistVM.playlists.isEmpty {
            Section {
                collapsibleHeader(
                    id: "playlists", title: "Playlists",
                    icon: "music.note.list",
                    trailing: AnyView(
                        Group {
                            if expanded.contains("playlists") {
                                Button(editMode.isEditing ? "Done" : "Edit") {
                                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                                }
                                .font(.callout)
                                .buttonStyle(.borderless)
                            }
                        }
                    )
                )
                if expanded.contains("playlists") {
                    ForEach(favorites) { pl in playlistRow(pl) }
                    ForEach(others) { pl in playlistRow(pl) }
                        .onMove { indices, newOffset in
                            var reordered = others
                            reordered.move(fromOffsets: indices, toOffset: newOffset)
                            Task { await playlistVM.reorderPlaylists(reordered) }
                        }
                        .onDelete { indices in
                            let toDelete = indices.map { others[$0] }
                            Task {
                                for pl in toDelete { await playlistVM.deletePlaylist(pl) }
                            }
                        }
                }
            }
        }

        ForEach(Self.orderedCategories(), id: \.self) { category in
            Section {
                collapsibleHeader(id: category, title: category,
                                  icon: Self.categoryIcon(category))
                if expanded.contains(category) {
                    ForEach(channels(in: category)) { channel in
                        Button {
                            onSelectChannel(channel)
                        } label: {
                            Label(channel.name, systemImage: channel.icon)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }

        Section {
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
        if searchVM.isSearching && searchVM.results.isEmpty {
            Section {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        } else if searchVM.results.isEmpty {
            Section {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            Section("Results") {
                ForEach(searchVM.results) { group in
                    Button {
                        Task {
                            await playerVM.playSearchResult(group)
                            dismissAll()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "music.note")
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
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Plays this result")
                }
            }
        }
    }

    // MARK: - Collapsible section header

    /// One row that doubles as the section header — chevron flips, taps
    /// toggle the matching key in `expanded`. We render our own header inside
    /// a Section (not a SwiftUI `header:`) so the chevron's tap area is part
    /// of the list rows, which gives consistent tap behaviour on iPhone/iPad.
    @ViewBuilder
    private func collapsibleHeader(id: String, title: String,
                                   icon: String? = nil,
                                   trailing: AnyView? = nil) -> some View {
        let isOpen = expanded.contains(id)
        HStack(spacing: 8) {
            // Only the icon + title + chevron toggle; trailing controls are
            // SIBLINGS (not children) so their taps aren't swallowed.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isOpen { expanded.remove(id) } else { expanded.insert(id) }
                }
            } label: {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("\(title), \(isOpen ? "expanded" : "collapsed")")
            .accessibilityHint("Double tap to \(isOpen ? "collapse" : "expand")")

            if let trailing { trailing }
        }
    }

    // SF Symbol per menu category.
    static func categoryIcon(_ category: String) -> String {
        switch category {
        case "Curated":      return "star"
        case "Ambient":      return "leaf"
        case "News":         return "newspaper"
        case "Contemporary": return "guitars"
        case "Audiobooks":   return "book"
        case "Lectures":     return "graduationcap"
        default:             return "music.note.list"
        }
    }

    // MARK: - Recently Played (collapsible + editable)

    @ViewBuilder
    private var recentlyPlayedSection: some View {
        Section {
            collapsibleHeader(
                id: "recently-played",
                title: "Recently Played",
                icon: "clock.arrow.circlepath",
                trailing: AnyView(
                    Group {
                        if expanded.contains("recently-played"), !recentlyPlayed.isEmpty {
                            Button(role: .destructive) {
                                Task {
                                    await playerVM.clearRecentlyPlayed()
                                    recentlyPlayed = []
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .font(.callout)
                            .accessibilityLabel("Clear all Recently Played")
                        }
                    }
                )
            )
            if expanded.contains("recently-played") {
                if recentlyPlayed.isEmpty {
                    Text("Nothing played yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentlyPlayed.prefix(20)) { track in
                        recentRow(track)
                    }
                    .onDelete { indices in
                        let toRemove = indices.map { recentlyPlayed[$0] }
                        Task {
                            for t in toRemove { await playerVM.removeFromRecentlyPlayed(t) }
                            recentlyPlayed = await playerVM.recentlyPlayedTracks(limit: 30)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentRow(_ track: Track) -> some View {
        Button {
            Task {
                await playerVM.playRecentTrack(track)
                dismissAll()
            }
        } label: {
            HStack(spacing: 10) {
                ArtworkThumbnail(track: track, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    await playerVM.removeFromRecentlyPlayed(track)
                    recentlyPlayed = await playerVM.recentlyPlayedTracks(limit: 30)
                }
            } label: { Label("Remove", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays this track")
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
            .background(.thinMaterial)
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
