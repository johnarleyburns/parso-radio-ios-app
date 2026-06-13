import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                ListenView()
                    .tabItem { Label("Listen", systemImage: "sparkles") }

                LibraryView()
                    .tabItem { Label("Library", systemImage: "music.note.list") }

                SearchTabView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
            }

            MiniPlayer()
                .environmentObject(playerVM)
                .padding(.bottom, 49)
        }
    }
}
