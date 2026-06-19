import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var playerVM: PlayerViewModel

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
    }
}

private extension View {
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom) {
            MiniPlayer()
        }
    }
}
