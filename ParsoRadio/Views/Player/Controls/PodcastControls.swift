import SwiftUI

struct PodcastControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        VStack(spacing: 18) {
            ScrubRow(tint: tint)

            HStack(spacing: 26) {
                TransportButton(system: "gobackward.15", size: 24, label: "Back 15 seconds") {
                    playerVM.seekBy(-15)
                }
                TransportButton(system: playerVM.isPlaying ? "pause.fill" : "play.fill",
                                size: 32, label: playerVM.isPlaying ? "Pause" : "Play",
                                prominent: true, tint: tint) { playerVM.togglePlayPause() }
                TransportButton(system: "goforward.30", size: 24, label: "Forward 30 seconds") {
                    playerVM.seekBy(30)
                }
            }

            HStack(spacing: 8) {
                EpisodeButton(showLabel: true).frame(maxWidth: .infinity)
                SpeedControl(showLabel: true).frame(maxWidth: .infinity)
                BookmarkButton(showLabel: true).frame(maxWidth: .infinity)
                SleepTimerButton(showLabel: true).frame(maxWidth: .infinity)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
