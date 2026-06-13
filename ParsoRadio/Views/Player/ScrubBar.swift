import SwiftUI

struct ScrubBar: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            if let duration = playerVM.trackDuration, duration > 0 {
                ProgressView(value: playerVM.currentPosition, total: duration)
                    .tint(tint)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            HStack {
                Text(playerVM.currentPosition.formattedTime)
                Spacer()
                if let duration = playerVM.trackDuration {
                    Text(duration.formattedTime)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.horizontal, 4)
    }
}
