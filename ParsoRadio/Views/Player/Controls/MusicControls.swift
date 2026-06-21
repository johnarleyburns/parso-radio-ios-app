import SwiftUI

struct MusicControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 22) {
                ShuffleButton()
                TransportButton(system: "backward.fill", size: 26, label: "Previous track") {
                    Task { await playerVM.goToPreviousTrack() }
                }
                TransportButton(system: playerVM.isPlaying ? "pause.fill" : "play.fill",
                                size: 30, label: playerVM.isPlaying ? "Pause" : "Play",
                                prominent: true, tint: tint) { playerVM.togglePlayPause() }
                TransportButton(system: "forward.fill", size: 26, label: "Next track") {
                    playerVM.skip()
                }
                RepeatButton()
            }
            HStack(spacing: 24) {
                SleepTimerButton()
                AirPlayButton().frame(width: 28, height: 28)
            }
        }
    }
}
