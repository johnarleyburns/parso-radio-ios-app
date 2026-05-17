import CoreHaptics

// Crisp transient "click" feedback for each seek tick. No-ops on hardware
// without haptics (Simulator / older devices), so it is CI-safe.
final class SeekHapticsController {
    private var engine: CHHapticEngine?

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        try? engine?.start()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        engine?.stoppedHandler = { _ in }
    }

    func tick(intensity: Float = 0.5, sharpness: Float = 0.8) {
        guard let engine,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []) else { return }
        let player = try? engine.makePlayer(with: pattern)
        try? player?.start(atTime: CHHapticTimeImmediate)
    }
}
