import Foundation

/// Pure decision logic for *when* to show the contribution toast. No UI, no
/// StoreKit, no I/O — deterministic given its inputs, so it's fully unit-tested
/// (the caller owns the persisted counters in UserDefaults). See
/// CONTRIBUTIONS-PROPOSAL.md §2.
///
/// Rules (from the locked plan):
///  • Never if the user opted out ("Don't ask again") or is already a supporter.
///  • Never on the first session, and at most once per session.
///  • Only after genuine engagement: ≥ minTracks played AND ≥ minSessions.
///  • After any prompt, snooze BOTH ≥ snoozeDays AND ≥ snoozeLaunches before
///    re-asking (so "Maybe later" means a real break, not next-launch nagging).
struct ContributionPromptEngine {
    var minTracks = 12
    var minSessions = 2
    var snoozeDays: Double = 7
    var snoozeLaunches = 5

    struct Inputs: Equatable {
        var tracksPlayed: Int
        var sessionCount: Int
        var isSupporter: Bool
        var optedOut: Bool
        var promptedThisSession: Bool
        var lastPromptAt: Date?
        var launchesSinceLastPrompt: Int
        var now: Date = Date()
    }

    func shouldPrompt(_ i: Inputs) -> Bool {
        // Hard stops.
        if i.optedOut || i.isSupporter { return false }
        if i.promptedThisSession { return false }
        // Engagement gates — never on the very first session.
        guard i.sessionCount >= minSessions else { return false }
        guard i.tracksPlayed >= minTracks else { return false }
        // Snooze after a previous prompt: BOTH the time and launch gate must pass.
        if let last = i.lastPromptAt {
            let daysSince = i.now.timeIntervalSince(last) / 86_400
            if daysSince < snoozeDays { return false }
            if i.launchesSinceLastPrompt < snoozeLaunches { return false }
        }
        return true
    }
}
