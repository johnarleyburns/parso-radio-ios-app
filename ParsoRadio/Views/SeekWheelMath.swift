import CoreGraphics
import Foundation

// Pure, dependency-free seek-wheel math. Free functions by design so they
// are trivially unit-testable without a view or a player.

/// Angle in radians (−π…π) of `point` relative to `center`.
func angle(from center: CGPoint, to point: CGPoint) -> Double {
    atan2(Double(point.y - center.y), Double(point.x - center.x))
}

/// Smallest signed delta (radians) from `from` to `to`.
/// Positive = clockwise; handles ±π wrap-around.
func clockwiseDelta(from: Double, to: Double) -> Double {
    var delta = to - from
    while delta >  .pi { delta -= 2 * .pi }
    while delta < -.pi { delta += 2 * .pi }
    return delta
}

/// Maps angular velocity (rad/s) to seconds-of-content per radian dragged,
/// scaled to track duration so short clips and long audiobooks both feel
/// natural. Slow = fine, fast = coarse.
func seekRate(for angularVelocity: Double, duration: TimeInterval) -> Double {
    let absVelocity = abs(angularVelocity)
    switch absVelocity {
    case ..<1.0:    return max(duration / (2 * .pi * 60), 1.0)
    case 1.0..<4.0: return duration / (2 * .pi * 4)
    default:        return duration / (2 * .pi * 0.5)
    }
}

/// Playback position → angle (radians), 12 o'clock start, clockwise.
func angle(for time: TimeInterval, duration: TimeInterval) -> Double {
    guard duration > 0 else { return -.pi / 2 }
    let fraction = min(max(time / duration, 0), 1)
    return fraction * 2 * .pi - .pi / 2
}
