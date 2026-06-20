import Foundation

// Pure, platform-independent playback POLICY (see PLAYBACK-DESIGN.md). No
// AVFoundation, no I/O, no global state — every type here is deterministic and
// unit-tested. The AVFoundation shell (ResilientAudioPlayer) is the only place
// that touches the player; it delegates all decisions to these types.

// MARK: - Failure classification

/// Whether a failure can plausibly be fixed by trying again.
enum PlaybackFailure: Equatable {
    case permanent   // 404/unsupported/decode error → skip now, never retry
    case transient   // timeout/5xx/connection lost/stall → retry with backoff
}

enum PlaybackFailureClassifier {
    /// Classify an HTTP status. 4xx are permanent EXCEPT the ones that genuinely
    /// self-heal (408 timeout, 425 too-early, 429 rate-limit). 5xx are transient.
    static func classify(httpStatus status: Int) -> PlaybackFailure {
        switch status {
        case 408, 425, 429: return .transient
        case 500...599:     return .transient
        case 400...499:     return .permanent
        default:            return .transient   // unknown → give it a chance
        }
    }

    /// Classify a URLError. Connectivity/timeout problems are transient; a bad
    /// URL or unsupported/undecodable resource is permanent.
    static func classify(urlError code: URLError.Code) -> PlaybackFailure {
        switch code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost,
             .resourceUnavailable:
            return .transient
        case .badURL, .unsupportedURL, .fileDoesNotExist,
             .cannotDecodeContentData, .cannotDecodeRawData:
            return .permanent
        default:
            return .transient
        }
    }
}

// MARK: - Retry / backoff + the two give-up caps

struct RetryPolicy: Equatable {
    var baseDelay: TimeInterval = 0.5
    var maxDelay: TimeInterval = 8
    var jitterFraction: Double = 0.25
    /// Transient retries for ONE item before skipping to the next.
    var maxAttemptsPerItem: Int = 4
    /// Items skipped with NO audio in between before giving up entirely.
    var maxConsecutiveSkips: Int = 4

    /// Exponential backoff with bounded jitter. `rand` ∈ [0,1) is injected so
    /// tests are deterministic; production passes `Double.random(in:)`.
    func delay(forAttempt k: Int, rand: Double = 0.5) -> TimeInterval {
        let exp = baseDelay * pow(2, Double(max(0, k)))
        let capped = min(maxDelay, exp)
        let jitter = capped * jitterFraction * (2 * rand - 1)   // ±jitterFraction
        return max(0, capped + jitter)
    }

    /// Retry only transient failures, and only while under the per-item cap.
    func shouldRetry(afterAttempt k: Int, failure: PlaybackFailure) -> Bool {
        failure == .transient && (k + 1) < maxAttemptsPerItem
    }
}

// MARK: - Stall state machine (generation-based)

/// The decision the controller makes when a stall watchdog fires. Pure mirror of
/// the logic hot-fixed into PlayerViewModel, now testable in isolation.
struct StallModel {
    let maxConsecutiveSkips: Int

    private(set) var loadGeneration = 0
    private(set) var readyGeneration = -1
    private(set) var confirmedGeneration = -1
    private(set) var consecutiveSkips = 0

    init(maxConsecutiveSkips: Int = 4) { self.maxConsecutiveSkips = maxConsecutiveSkips }

    enum Verdict: Equatable {
        case ignoreStale   // a watchdog from a previous load → no-op
        case healthy       // actually playing, or ready-while-paused → keep
        case skip          // stalled → advance to the next item
        case giveUp        // too many consecutive stalls with no audio → stop
    }

    /// Begin a new load; returns its generation. Cancels older watchdogs implicitly
    /// (their generation no longer matches).
    mutating func beginLoad() -> Int { loadGeneration += 1; return loadGeneration }

    /// The item reached `.readyToPlay` (playable, maybe paused).
    mutating func markReady(generation: Int) {
        if generation == loadGeneration { readyGeneration = generation }
    }

    /// A real periodic time tick — audio is genuinely progressing. Breaks the
    /// stall streak (the key fix: a mere resolve must NOT reset it, only real audio).
    mutating func confirmPlayback(generation: Int) {
        if generation == loadGeneration {
            confirmedGeneration = generation
            consecutiveSkips = 0
        }
    }

    /// A fresh user-chosen context (channel/playlist) → fresh skip budget.
    mutating func resetSkipStreak() { consecutiveSkips = 0 }

    /// Evaluate a fired stall watchdog. `autoPlay` distinguishes "we intended to
    /// play" (only a real tick proves health) from a paused load (ready is enough).
    mutating func evaluateStall(generation: Int, autoPlay: Bool) -> Verdict {
        guard generation == loadGeneration else { return .ignoreStale }
        if confirmedGeneration == generation { return .healthy }
        if !autoPlay && readyGeneration == generation { return .healthy }
        consecutiveSkips += 1
        return consecutiveSkips >= maxConsecutiveSkips ? .giveUp : .skip
    }
}

// MARK: - Single-flight registry

/// Thread-safe set of "operations in progress", keyed by id. Lets streaming and
/// downloading coalesce so a track is never fetched twice at once (the
/// double-fetch / "garbage prefetch" class). Reference type because callers share
/// one instance across concurrency domains; an NSLock keeps it cheap and
/// dependency-free (no actor hop on the hot path).
final class InFlightRegistry {
    private let lock = NSLock()
    private var ids = Set<String>()

    /// Try to claim the slot for `id`. Returns true iff THIS call acquired it
    /// (i.e. it was not already in flight) — the caller that gets true owns the
    /// fetch; others should back off.
    @discardableResult
    func begin(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ids.insert(id).inserted
    }

    func end(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        ids.remove(id)
    }

    func contains(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ids.contains(id)
    }
}

