import Foundation
import Combine

/// Curator Mode: the admin-only flow for reviewing candidate tracks per channel,
/// recording approve/reject/skip verdicts, and exporting the approved set as
/// JSON (the bundled manifest that curated channels play from at runtime). PIN
/// is **separate** from the Kids Mode parental PIN — different audience, different
/// privilege. The "unlocked" state is session-only; every relaunch re-asks the
/// PIN so the curator can hand the phone to anyone without leaving review
/// access open.
@MainActor
final class CuratorController: ObservableObject {
    static let shared = CuratorController()

    /// Session-only — NOT persisted. Every cold launch starts locked.
    @Published private(set) var isUnlocked = false

    private let pinKey = "curator.pin"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var hasPin: Bool { !(defaults.string(forKey: pinKey) ?? "").isEmpty }

    /// Set a fresh 4-digit curator PIN. No-op if it isn't 4 digits.
    func setPin(_ pin: String) {
        let p = KidsModeController.normalize(pin)
        guard p.count == 4 else { return }
        defaults.set(p, forKey: pinKey)
    }

    /// Try to unlock with `pin`. Returns whether it succeeded.
    @discardableResult
    func unlock(pin: String) -> Bool {
        let stored = defaults.string(forKey: pinKey) ?? ""
        guard !stored.isEmpty,
              KidsModeController.normalize(pin) == stored else { return false }
        isUnlocked = true
        return true
    }

    func lock() { isUnlocked = false }

    /// Channels eligible for curation — the registry-backed (iaQuery) ones.
    /// Those are the channels whose pool transitions from search-based to the
    /// approved-only manifest as their review is shipped.
    static func curatedChannels() -> [Channel] {
        Channel.defaults.filter { $0.iaQueryEntry != nil }
    }
}
