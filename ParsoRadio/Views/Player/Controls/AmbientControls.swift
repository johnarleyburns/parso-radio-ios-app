import SwiftUI

struct AmbientControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        VStack(spacing: 24) {
            TransportButton(system: playerVM.isPlaying ? "pause.fill" : "play.fill",
                            size: 40, label: playerVM.isPlaying ? "Pause" : "Play",
                            prominent: true, tint: tint) { playerVM.togglePlayPause() }
            HStack(spacing: 24) {
                SleepTimerButton(showLabel: true).frame(maxWidth: 130)
                AirPlayButton().frame(width: 28, height: 28)
            }
        }
    }
}
