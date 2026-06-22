import SwiftUI

struct AmbientControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        VStack(spacing: 22) {
            TransportButton(system: playerVM.isPlaying ? "pause.fill" : "play.fill",
                            size: 40, label: playerVM.isPlaying ? "Pause" : "Play",
                            prominent: true, tint: tint) { playerVM.togglePlayPause() }

            HStack(spacing: 8) {
                AirPlayButton().frame(maxWidth: .infinity)
                AmbientWebsiteButton().frame(maxWidth: .infinity)
                FavoriteButton(showLabel: true).frame(maxWidth: .infinity)
                SleepTimerButton(showLabel: true).frame(maxWidth: .infinity)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct AmbientWebsiteButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        if let track = playerVM.currentTrack,
           track.source == "freesound",
           let soundID = track.id.hasPrefix("freesound-") ? String(track.id.dropFirst("freesound-".count)) : nil {
            Link(destination: URL(string: "https://freesound.org/sounds/\(soundID)/")!) {
                VStack(spacing: 4) {
                    Image(systemName: "globe").font(.title3)
                    Text("Website").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("View on Freesound")
        } else {
            VStack(spacing: 4) {
                Image(systemName: "globe").font(.title3)
                    .foregroundStyle(.secondary)
                    .opacity(0.4)
                Text("Website").font(.caption2)
                    .foregroundStyle(.secondary)
                    .opacity(0.4)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
