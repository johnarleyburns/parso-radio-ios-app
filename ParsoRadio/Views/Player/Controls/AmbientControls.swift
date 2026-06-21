import SwiftUI

struct AmbientControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        TransportButton(system: playerVM.isPlaying ? "pause.fill" : "play.fill",
                        size: 40, label: playerVM.isPlaying ? "Pause" : "Play",
                        prominent: true, tint: tint) { playerVM.togglePlayPause() }
    }
}
