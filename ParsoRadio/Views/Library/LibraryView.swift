import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var deps: AppDependencies
    @EnvironmentObject var offlineService: OfflineDownloadService
    @State private var downloadedTracks: [Track] = []
    @State private var downloadsLoading = true

    var body: some View {
        NavigationStack {
            List {
                Section("Playlists") {
                    NavigationLink {
                        PlaylistListView()
                            .environmentObject(playlistVM)
                            .environmentObject(playerVM)
                            .environmentObject(offlineService)
                    } label: {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                }

                Section {
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
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .task {
                await loadDownloads()
            }
            .refreshable {
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
