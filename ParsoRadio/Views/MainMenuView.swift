import SwiftUI

struct MainMenuView: View {
    let onSelectChannel: (Channel) -> Void
    let dismissAll: () -> Void          // close the whole menu (back to player)

    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @Environment(\.dismiss) private var dismiss

    @State private var showSearch = false
    @State private var showAbout = false
    @State private var recentlyPlayed: [Track] = []
    // Section IDs currently expanded. Empty = all collapsed (the default).
    // Includes special keys "recently-played" and "playlists" plus each
    // category string.
    @State private var expanded: Set<String> = []
    @State private var editingRecents: Bool = false

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

    // A playlist row ALWAYS opens the playlist detail (never starts playing).
    // Play / Resume / Shuffle live inside the detail screen.
    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        NavigationLink {
            PlaylistDetailView(playlist: playlist, dismissAll: dismissAll)
                .environmentObject(playlistVM)
                .environmentObject(playerVM)
                .environmentObject(offlineService)
        } label: {
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
        NavigationStack {
            List {
                Section {
                    Button {
                        showSearch = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .font(.body).padding(.vertical, 2)
                    }
                    .foregroundStyle(.primary)
                }

                if !recentlyPlayed.isEmpty {
                    recentlyPlayedSection
                }

                // Persisted order (Favorites pinned first, then user order).
                let favorites = playlistVM.playlists.filter { $0.isFavorites }
                let others    = playlistVM.playlists.filter { !$0.isFavorites }
                if !playlistVM.playlists.isEmpty {
                    Section {
                        collapsibleHeader(id: "playlists", title: "Playlists")
                        if expanded.contains("playlists") {
                            ForEach(favorites) { pl in playlistRow(pl) }
                            ForEach(others) { pl in playlistRow(pl) }
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
                        collapsibleHeader(id: category, title: category)
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
            .listStyle(.insetGrouped)
            .navigationTitle("Parso Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchView(dismissAll: dismissAll)
                    .environmentObject(playlistVM)
                    .environmentObject(playerVM)
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

    // MARK: - Collapsible section header

    /// One row that doubles as the section header — chevron flips, taps
    /// toggle the matching key in `expanded`. We render our own header inside
    /// a Section (not a SwiftUI `header:`) so the chevron's tap area is part
    /// of the list rows, which gives consistent tap behaviour on iPhone/iPad.
    @ViewBuilder
    private func collapsibleHeader(id: String, title: String,
                                   trailing: AnyView? = nil) -> some View {
        let isOpen = expanded.contains(id)
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                if isOpen { expanded.remove(id) } else { expanded.insert(id) }
            }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
                Spacer()
                if let trailing { trailing }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title), \(isOpen ? "expanded" : "collapsed")")
        .accessibilityHint("Double tap to \(isOpen ? "collapse" : "expand")")
    }

    // MARK: - Recently Played (collapsible + editable)

    @ViewBuilder
    private var recentlyPlayedSection: some View {
        Section {
            collapsibleHeader(
                id: "recently-played",
                title: "Recently Played",
                trailing: AnyView(
                    Group {
                        if expanded.contains("recently-played") {
                            HStack(spacing: 12) {
                                Button(editingRecents ? "Done" : "Edit") {
                                    editingRecents.toggle()
                                }
                                .font(.caption)
                                Button(role: .destructive) {
                                    Task {
                                        await playerVM.clearRecentlyPlayed()
                                        recentlyPlayed = []
                                        editingRecents = false
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .font(.caption)
                                .disabled(recentlyPlayed.isEmpty)
                                .accessibilityLabel("Clear all Recently Played")
                            }
                        }
                    }
                )
            )
            if expanded.contains("recently-played") {
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

    @ViewBuilder
    private func recentRow(_ track: Track) -> some View {
        Button {
            guard !editingRecents else { return }
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
