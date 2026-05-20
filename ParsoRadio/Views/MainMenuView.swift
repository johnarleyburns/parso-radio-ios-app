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

    // Fixed section order (item 1). Alphabetical WITHIN each (item 9).
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

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack(spacing: 8) {
            // Tapping the playlist RESUMES by default (exact saved spot, or
            // from the top if nothing saved) and returns to the player.
            Button {
                Task {
                    await playerVM.resumePlaylist(playlist)
                    dismissAll()
                }
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
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(playlist.name), \(playlistVM.trackCount(for: playlist)) tracks")
            .accessibilityHint("Resumes where you left off, or plays from the start")

            // Explicit path to play-from-top / shuffle / edit / add.
            NavigationLink {
                PlaylistDetailView(playlist: playlist, dismissAll: dismissAll)
                    .environmentObject(playlistVM)
                    .environmentObject(playerVM)
                    .environmentObject(offlineService)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("\(playlist.name) options")
            .accessibilityHint("Opens the playlist to play from the top, shuffle, or edit")
        }
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
                    Section("Recently Played") {
                        ForEach(recentlyPlayed.prefix(20)) { track in
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
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Plays this track")
                        }
                    }
                }

                // Persisted order (Favorites pinned first, then user order).
                let favorites = playlistVM.playlists.filter { $0.isFavorites }
                let others    = playlistVM.playlists.filter { !$0.isFavorites }
                if !playlistVM.playlists.isEmpty {
                    Section {
                        ForEach(favorites) { playlist in
                            playlistRow(playlist)
                        }
                        ForEach(others) { playlist in
                            playlistRow(playlist)
                        }
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
                    } header: {
                        HStack {
                            Text("Playlists")
                            Spacer()
                            EditButton()
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }

                ForEach(Self.orderedCategories(), id: \.self) { category in
                    Section(category) {
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
            // Presented FROM the menu (not after dismissing it) so there is no
            // flash of the player screen between transitions (item 10).
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
