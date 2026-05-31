import Foundation
import Combine

/// Curator Mode: the admin-only flow for reviewing candidate tracks per channel,
/// recording approve/reject/skip verdicts, and exporting the approved set as
/// JSON (the bundled manifest curated channels play from at runtime). The PIN
/// is HARDCODED ("128800") — this is a personal admin tool, not a per-user
/// security boundary, and a fixed PIN keeps the build self-contained without a
/// stored PIN that could drift between devices. The "unlocked" state is
/// session-only; every relaunch re-asks the PIN.
@MainActor
final class CuratorController: ObservableObject {
    static let shared = CuratorController()

    /// The single, hardcoded curator PIN.
    static let pin = "128800"

    /// Session-only — NOT persisted. Every cold launch starts locked.
    @Published private(set) var isUnlocked = false

    init() {}

    /// Always true — the PIN exists by definition (hardcoded).
    var hasPin: Bool { true }

    /// Try to unlock with `pin`. Returns whether it succeeded. Strips non-digit
    /// characters tolerantly — does NOT use KidsModeController.normalize because
    /// that caps at 4 chars (the kids PIN length) which would silently break
    /// this 6-digit one.
    @discardableResult
    func unlock(pin: String) -> Bool {
        let digits = String(pin.filter(\.isNumber))
        guard digits == Self.pin else { return false }
        isUnlocked = true
        return true
    }

    func lock() { isUnlocked = false }

    /// Channels eligible for curation — ONLY the "Curated" category (curated
    /// classical / world / Children's). Excludes News, Lectures, Audiobooks
    /// (LibriVox book channels), For-You, Ambient. Curated audio classics
    /// like Great Books still appear because they live in "Curated".
    static func curatedChannels() -> [Channel] {
        Channel.defaults.filter { $0.category == "Curated" && $0.iaQueryEntry != nil }
    }
}
