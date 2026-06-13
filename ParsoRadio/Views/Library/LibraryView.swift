import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var deps: AppDependencies
    @EnvironmentObject var offlineService: OfflineDownloadService

    var body: some View {
        NavigationStack {
            List {
                Section("Playlists") {
                    NavigationLink {
                        PlaylistListView()
                    } label: {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                }

                Section {
                    NavigationLink {
                        FavoritesScreen()
                            .environmentObject(favorites)
                    } label: {
                        Label("Favorites", systemImage: "heart")
                    }

                    NavigationLink {
                        RecentlyPlayedScreen(dismissAll: {})
                    } label: {
                        Label("Recently Played", systemImage: "clock")
                    }

                    NavigationLink {
                        Text("Downloads")
                    } label: {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
        }
    }
}
