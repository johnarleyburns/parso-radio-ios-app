import Foundation
import Combine

/// Parental "Kids Mode": when on, the app exposes ONLY the children's channels,
/// hides Search/News/Settings and the contribution prompt, and starts on a kids
/// channel — so a phone can be safely handed to a child (a core mission for kids
/// in low-income regions who can't pay for a subscription). A 4-digit PIN gates
/// turning it OFF. Shared singleton (like NetworkMonitor) so the menu, launch,
/// and the toast can all observe it.
///
/// The PIN lives in UserDefaults: this is a PARENTAL GATE, not a security
/// boundary, so plaintext-in-defaults is acceptable and keeps it dependency-free.
@MainActor
final class KidsModeController: ObservableObject {
    static let shared = KidsModeController()

    /// The only channels reachable while Kids Mode is on.
    static let allowedChannelIDs: Set<String> = ["childrens-songs", "childrens-books"]

    @Published private(set) var isEnabled: Bool

    private let enabledKey = "kidsMode.enabled"
    private let pinKey = "kidsMode.pin"
    // Injectable so unit tests use an isolated store instead of the shared one.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: enabledKey)
    }

    /// Turn Kids Mode ON with a fresh 4-digit PIN. No-op if the PIN isn't 4 digits.
    func enable(pin: String) {
        let p = Self.normalize(pin)
        guard p.count == 4 else { return }
        defaults.set(p, forKey: pinKey)
        defaults.set(true, forKey: enabledKey)
        isEnabled = true
    }

    /// Turn Kids Mode OFF — only if `pin` matches. Returns whether it succeeded.
    @discardableResult
    func disable(pin: String) -> Bool {
        guard verify(pin: pin) else { return false }
        defaults.set(false, forKey: enabledKey)
        isEnabled = false
        return true
    }

    func verify(pin: String) -> Bool {
        let stored = defaults.string(forKey: pinKey) ?? ""
        return !stored.isEmpty && Self.normalize(pin) == stored
    }

    /// The children's channels, in `Channel.defaults` order.
    static func allowedChannels() -> [Channel] {
        Channel.defaults.filter { allowedChannelIDs.contains($0.id) }
    }

    /// When Kids Mode is turned on, should we immediately redirect to a
    /// children's channel? True when there's no current channel, or when it
    /// isn't an allowed kids channel — so back-track can never reach non-kid
    /// content right after enabling.
    static func shouldRedirect(fromChannelId currentChannelId: String?) -> Bool {
        guard let id = currentChannelId else { return true }
        return !allowedChannelIDs.contains(id)
    }

    /// Keep only digits, cap at 4.
    static func normalize(_ s: String) -> String {
        String(s.filter(\.isNumber).prefix(4))
    }
}
