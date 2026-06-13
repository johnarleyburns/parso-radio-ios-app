import SwiftUI

struct SpeedControl: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        HStack(spacing: 16) {
            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button {
                    playerVM.setPlaybackRate(rate)
                } label: {
                    Text(rate.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    .background(
                        abs(playerVM.playbackRate - rate) < 0.05
                            ? Color.blue : Color(.systemGray5)
                    )
                    .foregroundStyle(
                        abs(playerVM.playbackRate - rate) < 0.05
                            ? .white : .primary
                    )
                        .clipShape(Capsule())
                }
            }
        }
    }
}
