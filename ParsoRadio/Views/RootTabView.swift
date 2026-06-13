import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        TabView {
            ListenView()
                .miniPlayerDock()
                .tabItem { Label("Listen", systemImage: "sparkles") }

            LibraryView()
                .miniPlayerDock()
                .tabItem { Label("Library", systemImage: "music.note.list") }

            SearchTabView()
                .miniPlayerDock()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
    }
}

private extension View {
    func miniPlayerDock() -> some View {
        safeAreaInset(edge: .bottom) { MiniPlayer() }
    }
}
