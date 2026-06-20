import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var deps: AppDependencies
    @EnvironmentObject var offlineService: OfflineDownloadService
    @State private var downloadedTracks: [Track] = []
    @State private var downloadsLoading = true
    @State private var showCreateAlert = false
    @State private var newPlaylistName = ""
    @State private var playlistToRename: Playlist? = nil
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("My Library") {
                    NavigationLink {
                        FavoritesScreen()
                            .environmentObject(favorites)
                            .environmentObject(playerVM)
                            .environmentObject(playlistVM)
                    } label: {
                        Label("Favorites", systemImage: "heart")
                    }

                    NavigationLink {
                        RecentlyPlayedScreen(dismissAll: {})
                            .environmentObject(playerVM)
                    } label: {
                        Label("Recently Played", systemImage: "clock")
                    }

                    NavigationLink {
                        downloadsList
                    } label: {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                }

                Section("My Playlists") {
                    if playlistVM.playlists.filter({ !$0.isFavorites }).isEmpty {
                        Text("No playlists yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playlistVM.playlists.filter { !$0.isFavorites }) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist, dismissAll: nil)
                                    .environmentObject(playlistVM)
                                    .environmentObject(playerVM)
                                    .environmentObject(offlineService)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                        .font(.body)
                                    Text("\(playlistVM.trackCount(for: playlist)) tracks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !playlist.isFavorites {
                                    Button(role: .destructive) {
                                        Task { await playlistVM.deletePlaylist(playlist) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        playlistToRename = playlist
                                        renameText = playlist.name
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Playlist")
                }
            }
            .alert("New Playlist", isPresented: $showCreateAlert) {
                TextField("Name", text: $newPlaylistName)
                Button("Create") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        await playlistVM.createPlaylist(name: name)
                        newPlaylistName = ""
                    }
                }
                Button("Cancel", role: .cancel) { newPlaylistName = "" }
            }
            .alert("Rename Playlist", isPresented: Binding(
                get: { playlistToRename != nil },
                set: { if !$0 { playlistToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let p = playlistToRename {
                        Task {
                            await playlistVM.renamePlaylist(p, to: renameText)
                            playlistToRename = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) { playlistToRename = nil }
            }
            .task {
                await playlistVM.loadPlaylists()
                await loadDownloads()
            }
            .refreshable {
                await playlistVM.loadPlaylists()
                await loadDownloads()
            }
        }
    }

    private var downloadsList: some View {
        Group {
            if downloadsLoading {
                ProgressView("Loading downloads...")
            } else if downloadedTracks.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloaded tracks will appear here for offline listening.")
                )
            } else {
                List {
                    Button(role: .destructive) {
                        Task {
                            await offlineService.deleteAllDownloads()
                            await loadDownloads()
                        }
                    } label: {
                        Label("Clear All Downloads", systemImage: "trash")
                    }

                    ForEach(downloadedTracks) { track in
                        Button {
                            Task { await playerVM.playSingleTrack(track) }
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkThumbnail(track: track, size: 44)
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
                                if track.duration > 0 {
                                    Text(track.duration.formattedTime)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    await offlineService.removeOffline(track: track)
                                    await loadDownloads()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadDownloads() async {
        downloadsLoading = true
        downloadedTracks = await deps.db.fetchAllDownloadedTracks()
        downloadsLoading = false
    }
}
