import SwiftUI

struct ScrubBar: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        if let duration = playerVM.trackDuration, duration > 0 {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : playerVM.currentPosition },
                    set: { scrubValue = $0 }
                ),
                in: 0...duration
            ) { editing in
                if editing {
                    isScrubbing = true
                    scrubValue = playerVM.currentPosition
                } else {
                    playerVM.seek(to: scrubValue)
                    isScrubbing = false
                }
            }
            .tint(tint)
            .accessibilityLabel("Seek")
            .accessibilityIdentifier("player.scrub.slider")
        } else {
            ProgressView().progressViewStyle(.linear)
        }
    }
}
