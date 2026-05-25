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

// MARK: - Source selection (L > D > S, single-flight)

struct SourceInputs: Equatable {
    var trackID: String
    var localCompletePath: String?   // finished offline/imported file on disk
    var downloadInFlight: Bool       // DownloadManager already fetching this id
    var isPerFileURL: Bool           // id contains "/" → streamURL is direct (no resolve)
}

enum PlaybackSource: Equatable {
    case localComplete(path: String)   // play the file directly
    case joinInFlightDownload(id: String) // a download is running → join it, don't double-fetch
    case stream(resolveNeeded: Bool)   // open a network stream (resolve IA id first unless per-file)
}

enum SourceSelector {
    /// Priority L > D > S. Never opens a competing stream for an id already being
    /// downloaded (the double-fetch / garbage-prefetch bug).
    static func select(_ i: SourceInputs) -> PlaybackSource {
        if let path = i.localCompletePath { return .localComplete(path: path) }
        if i.downloadInFlight { return .joinInFlightDownload(id: i.trackID) }
        return .stream(resolveNeeded: !i.isPerFileURL)
    }
}

// MARK: - Throughput estimate (EWMA)

struct ThroughputEstimator: Equatable {
    private(set) var bytesPerSecond: Double?
    var alpha: Double = 0.3

    mutating func record(bytes: Int, over seconds: Double) {
        guard seconds > 0, bytes > 0 else { return }
        let sample = Double(bytes) / seconds
        bytesPerSecond = bytesPerSecond.map { alpha * sample + (1 - alpha) * $0 } ?? sample
    }

    /// Wall-seconds to prebuffer `seconds` of audio at `bitrateBytesPerSec`.
    func prebufferETA(seconds: Double, bitrateBytesPerSec: Double) -> Double? {
        guard let tp = bytesPerSecond, tp > 0, bitrateBytesPerSec > 0 else { return nil }
        return seconds * bitrateBytesPerSec / tp
    }

    /// Highest available bitrate that fits within `safety`·throughput so playback
    /// can keep up. Unknown throughput → the best available; none fit → the smallest.
    func bestBitrate(from available: [Double], safety: Double = 0.8) -> Double? {
        guard !available.isEmpty else { return nil }
        guard let tp = bytesPerSecond else { return available.max() }
        let budget = tp * safety
        return available.filter { $0 <= budget }.max() ?? available.min()
    }
}

// MARK: - Cache eviction (LRU, pinned-safe)

struct CacheEntry: Equatable {
    let id: String
    let size: Int64
    let lastAccess: Date
    let pinned: Bool   // user offline download → never evicted
}

enum CacheEvictionPolicy {
    /// Ids to evict to bring total size under `maxBytes`, least-recently-used
    /// first. Pinned entries are never evicted; if pinned alone exceeds the cap
    /// we evict every unpinned entry (best effort).
    static func evictions(_ entries: [CacheEntry], maxBytes: Int64) -> [String] {
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > maxBytes else { return [] }
        var over = total - maxBytes
        var out: [String] = []
        for e in entries.filter({ !$0.pinned }).sorted(by: { $0.lastAccess < $1.lastAccess }) {
            if over <= 0 { break }
            out.append(e.id)
            over -= e.size
        }
        return out
    }
}
