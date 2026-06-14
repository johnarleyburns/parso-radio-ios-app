import SwiftUI

struct SpeedControl: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    private let rates: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private var label: String {
        playerVM.playbackRate.formatted(.number.precision(.fractionLength(0...2))) + "\u{00d7}"
    }

    var body: some View {
        Menu {
            ForEach(rates, id: \.self) { rate in
                Button {
                    playerVM.setPlaybackRate(rate)
                } label: {
                    HStack {
                        Text(rate.formatted(.number.precision(.fractionLength(0...2))) + "\u{00d7}")
                        if abs(playerVM.playbackRate - rate) < 0.05 {
                            Spacer(); Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "speedometer").font(.title3)
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(abs(playerVM.playbackRate - 1.0) < 0.05 ? .primary : Color.accentColor)
        }
        .accessibilityLabel("Playback speed, \(label)")
    }
}
