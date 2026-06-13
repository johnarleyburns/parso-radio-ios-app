import SwiftUI

struct SearchTabView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel

    var body: some View {
        SearchView()
            .environmentObject(playerVM)
            .environmentObject(playlistVM)
    }
}
