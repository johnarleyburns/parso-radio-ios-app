import Foundation
import Combine

/// Owns the contribution-toast lifecycle: the persisted engagement counters, the
/// pure decision (ContributionPromptEngine), and the show/snooze/opt-out state.
/// The view layer observes `showToast`; the player bumps the track counter via
/// the static `recordTrackPlayed` (no coordinator reference needed).
@MainActor
final class ContributionCoordinator: ObservableObject {
    @Published var showToast = false

    private let engine = ContributionPromptEngine()
    private let store: ContributionStore
    private let defaults: UserDefaults
    private var promptedThisSession = false

    private enum Key {
        static let tracks        = "contrib.tracksPlayed"
        static let sessions      = "contrib.sessionCount"
        static let optedOut      = "contrib.optedOut"
        static let lastPrompt    = "contrib.lastPromptAt"
        static let launchesSince = "contrib.launchesSinceLastPrompt"
    }

    init(store: ContributionStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    /// Once per launch: a new session, a launch toward the snooze gate, reset the
    /// once-per-session guard.
    func beginSession() {
        defaults.set(defaults.integer(forKey: Key.sessions) + 1, forKey: Key.sessions)
        defaults.set(defaults.integer(forKey: Key.launchesSince) + 1, forKey: Key.launchesSince)
        promptedThisSession = false
    }

    /// Bump the engagement counter on each genuine (non-ambient) track play.
    /// Static so PlayerViewModel needn't hold a coordinator reference.
    static func recordTrackPlayed(defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: Key.tracks) + 1, forKey: Key.tracks)
    }

    /// Evaluate at a natural break; raises the toast iff the engine approves.
    func evaluate() {
        guard !showToast else { return }
        let inputs = ContributionPromptEngine.Inputs(
            tracksPlayed: defaults.integer(forKey: Key.tracks),
            sessionCount: defaults.integer(forKey: Key.sessions),
            isSupporter: store.isSupporter,
            optedOut: defaults.bool(forKey: Key.optedOut),
            promptedThisSession: promptedThisSession,
            lastPromptAt: defaults.object(forKey: Key.lastPrompt) as? Date,
            launchesSinceLastPrompt: defaults.integer(forKey: Key.launchesSince),
            now: Date())
        guard engine.shouldPrompt(inputs) else { return }
        promptedThisSession = true
        defaults.set(Date(), forKey: Key.lastPrompt)   // arms the 7-day snooze
        defaults.set(0, forKey: Key.launchesSince)      // arms the 5-launch snooze
        showToast = true
    }

    func dismissToast() { showToast = false }                                  // "Maybe later"
    func optOutForever() { defaults.set(true, forKey: Key.optedOut); showToast = false } // "Don't ask again"
}
