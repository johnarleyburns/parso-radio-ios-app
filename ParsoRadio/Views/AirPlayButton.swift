import SwiftUI
import AVKit

/// System AirPlay route picker bridged into SwiftUI. Tapping it surfaces the
/// iOS route picker (HomePod, Apple TV, AirPods, etc.). On the simulator the
/// picker may have no targets but the button still renders.
struct AirPlayButton: UIViewRepresentable {
    var activeTintColor: UIColor = .systemBlue
    var inactiveTintColor: UIColor = .label

    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.activeTintColor = activeTintColor
        v.tintColor = inactiveTintColor
        v.prioritizesVideoDevices = false
        v.setContentHuggingPriority(.required, for: .horizontal)
        v.setContentHuggingPriority(.required, for: .vertical)
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.activeTintColor = activeTintColor
        uiView.tintColor = inactiveTintColor
    }
}
