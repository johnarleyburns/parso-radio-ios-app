import SwiftUI

struct ScrubBar: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        if let duration = playerVM.trackDuration, duration > 0 {
            ProgressView(value: playerVM.currentPosition, total: duration)
                .tint(tint)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
        }
    }
}
