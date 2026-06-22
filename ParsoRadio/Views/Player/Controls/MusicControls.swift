import SwiftUI

struct MusicControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 22) {
                ShuffleButton()
                    .disabled(playerVM.currentTrack == nil || playerVM.isLoading)
                TransportButton(system: "backward.fill", size: 26, label: "Previous track") {
                    Task { await playerVM.goToPreviousTrack() }
                }
                .disabled(playerVM.currentTrack == nil || playerVM.isLoading)
                TransportButton(system: playerVM.isPlaying ? "pause.fill" : "play.fill",
                                size: 30, label: playerVM.isPlaying ? "Pause" : "Play",
                                prominent: true, tint: tint) { playerVM.togglePlayPause() }
                .disabled(playerVM.currentTrack == nil || playerVM.isLoading)
                TransportButton(system: "forward.fill", size: 26, label: "Next track") {
                    playerVM.skip()
                }
                .disabled(playerVM.currentTrack == nil || playerVM.isLoading)
                RepeatButton()
                    .disabled(playerVM.currentTrack == nil || playerVM.isLoading)
            }

            HStack(spacing: 8) {
                AirPlayButton().frame(maxWidth: .infinity)
                AlbumTracksButton(showLabel: true).frame(maxWidth: .infinity)
                FavoriteButton(showLabel: true).frame(maxWidth: .infinity)
                SleepTimerButton(showLabel: true).frame(maxWidth: .infinity)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
