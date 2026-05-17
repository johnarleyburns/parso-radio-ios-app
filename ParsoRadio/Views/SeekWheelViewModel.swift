import CoreGraphics
import Foundation

// Owns the drag→seek pipeline. No playback state of its own: the caller
// sets currentTime/duration/onSeek, draws the arc from currentTime, and
// updates currentTime from the player's periodic observer. This separation
// is what makes the whole pipeline unit-testable via simulateDrag().
final class SeekWheelViewModel: ObservableObject {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var onSeek: (TimeInterval) -> Void = { _ in }

    private var previousAngle: Double?
    private var previousTimestamp: Date?
    private var accumulatedAngleForHaptics: Double = 0
    private let hapticTickInterval: Double = 5 * .pi / 180   // 5°
    private let hapticsController = SeekHapticsController()

    func onAppear() { hapticsController.prepare() }

    func angularVelocity(currentAngle: Double, now: Date) -> Double {
        guard let prev = previousAngle, let prevTime = previousTimestamp else { return 0 }
        let dt = now.timeIntervalSince(prevTime)
        guard dt > 0 else { return 0 }
        return clockwiseDelta(from: prev, to: currentAngle) / dt
    }

    /// DragGesture .onChanged
    func handleDrag(location: CGPoint, center: CGPoint, now: Date = Date()) {
        let touchAngle = angle(from: center, to: location)
        let velocity   = angularVelocity(currentAngle: touchAngle, now: now)
        let delta      = clockwiseDelta(from: previousAngle ?? touchAngle, to: touchAngle)
        let rate       = seekRate(for: velocity, duration: duration)
        let newTime    = min(max(currentTime + delta * rate, 0), max(duration, 0))

        currentTime = newTime
        onSeek(newTime)

        accumulatedAngleForHaptics += abs(delta)
        while accumulatedAngleForHaptics >= hapticTickInterval {
            accumulatedAngleForHaptics -= hapticTickInterval
            let intensity = Float(min(0.3 + abs(velocity) * 0.07, 1.0))
            hapticsController.tick(intensity: intensity, sharpness: 0.8)
        }

        previousAngle     = touchAngle
        previousTimestamp = now
    }

    /// DragGesture .onEnded
    func handleDragEnded() {
        previousAngle              = nil
        previousTimestamp          = nil
        accumulatedAngleForHaptics = 0
    }

    // Test hook: drive a full drag without a view or a player.
    func simulateDrag(fromAngle: Double, toAngle: Double, velocity: Double) {
        let fakeNow  = Date()
        let span     = abs(clockwiseDelta(from: fromAngle, to: toAngle))
        let fakePast = fakeNow.addingTimeInterval(-span / max(velocity, 0.001))
        previousAngle     = fromAngle
        previousTimestamp = fakePast
        let fakeCenter   = CGPoint(x: 0, y: 0)
        let fakeLocation = CGPoint(x: cos(toAngle), y: sin(toAngle))
        handleDrag(location: fakeLocation, center: fakeCenter, now: fakeNow)
    }
}
