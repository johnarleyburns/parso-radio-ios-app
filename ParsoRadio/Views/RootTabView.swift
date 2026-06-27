import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService

    var body: some View {
        TabView {
            ListenView()
                .miniPlayerInset()
                .tabItem { Label("Listen", systemImage: "sparkles") }

            LibraryView()
                .miniPlayerInset()
                .tabItem { Label("Library", systemImage: "music.note.list") }

            SearchTabView()
                .miniPlayerInset()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        // Album/chapter/episode list opened from the now-playing surface. The
        // full player has already dismissed (mini player stays); audio keeps
        // playing untouched until a row is tapped.
        .sheet(item: $playerVM.surfaceListRequest) { request in
            surfaceList(for: request)
        }
        // Re-opens the full player after a row is picked from a surface list.
        .fullScreenCover(isPresented: $playerVM.shouldPresentNowPlaying) {
            NowPlayingSheet()
                .environmentObject(playerVM)
                .environmentObject(favorites)
                .environmentObject(playlistVM)
                .environmentObject(offlineService)
        }
    }

    @ViewBuilder
    private func surfaceList(for request: PlayerViewModel.SurfaceListRequest) -> some View {
        switch request {
        case let .album(identifier, title, creator):
            ItemDetailView(identifier: identifier, title: title, creator: creator,
                           kind: .album, autoPlayOnLoad: false, presentedFromSurface: true)
                .environmentObject(playerVM)
                .environmentObject(favorites)
        case .chapters:
            NavigationStack {
                ChapterListView(presentedFromSurface: true)
                    .environmentObject(playerVM)
            }
        case .episodes:
            NavigationStack {
                EpisodeListView(presentedFromSurface: true)
                    .environmentObject(playerVM)
            }
        }
    }
}

private extension View {
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom) {
            MiniPlayer()
        }
    }
}
