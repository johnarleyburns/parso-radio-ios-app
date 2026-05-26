import XCTest
@testable import ParsoMusic

final class PlaybackResilienceTests: XCTestCase {

    // MARK: - Failure classification

    func testHTTPClassification() {
        XCTAssertEqual(PlaybackFailureClassifier.classify(httpStatus: 404), .permanent)
        XCTAssertEqual(PlaybackFailureClassifier.classify(httpStatus: 410), .permanent)
        XCTAssertEqual(PlaybackFailureClassifier.classify(httpStatus: 451), .permanent)
        XCTAssertEqual(PlaybackFailureClassifier.classify(httpStatus: 403), .permanent)
        // self-healing 4xx are transient
        XCTAssertEqual(PlaybackFailureClassifier.classify(httpStatus: 408), .transient)
        XCTAssertEqual(PlaybackFailureClassifier.classify(httpStatus: 429), .transient)
        // server errors transient
        XCTAssertEqual(PlaybackFailureClassifier.classify(httpStatus: 500), .transient)
        XCTAssertEqual(PlaybackFailureClassifier.classify(httpStatus: 503), .transient)
    }

    func testURLErrorClassification() {
        XCTAssertEqual(PlaybackFailureClassifier.classify(urlError: .timedOut), .transient)
        XCTAssertEqual(PlaybackFailureClassifier.classify(urlError: .networkConnectionLost), .transient)
        XCTAssertEqual(PlaybackFailureClassifier.classify(urlError: .notConnectedToInternet), .transient)
        XCTAssertEqual(PlaybackFailureClassifier.classify(urlError: .badURL), .permanent)
        XCTAssertEqual(PlaybackFailureClassifier.classify(urlError: .unsupportedURL), .permanent)
        XCTAssertEqual(PlaybackFailureClassifier.classify(urlError: .cannotDecodeContentData), .permanent)
    }

    // MARK: - Retry / backoff

    func testBackoffIsMonotonicAndCapped() {
        let p = RetryPolicy()
        // With rand=0.5 (no jitter), delays double until capped at maxDelay.
        XCTAssertEqual(p.delay(forAttempt: 0, rand: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(p.delay(forAttempt: 1, rand: 0.5), 1.0, accuracy: 1e-9)
        XCTAssertEqual(p.delay(forAttempt: 2, rand: 0.5), 2.0, accuracy: 1e-9)
        XCTAssertEqual(p.delay(forAttempt: 3, rand: 0.5), 4.0, accuracy: 1e-9)
        XCTAssertEqual(p.delay(forAttempt: 10, rand: 0.5), 8.0, accuracy: 1e-9, "capped at maxDelay")
    }

    func testBackoffJitterBounds() {
        let p = RetryPolicy()
        let base = p.delay(forAttempt: 2, rand: 0.5)         // 2.0
        let low  = p.delay(forAttempt: 2, rand: 0.0)         // −25%
        let high = p.delay(forAttempt: 2, rand: 1.0)         // +25%
        XCTAssertEqual(low,  base * 0.75, accuracy: 1e-9)
        XCTAssertEqual(high, base * 1.25, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(low, 0, "delay never negative")
    }

    func testShouldRetryRespectsClassAndCap() {
        let p = RetryPolicy(maxAttemptsPerItem: 4)
        XCTAssertFalse(p.shouldRetry(afterAttempt: 0, failure: .permanent), "never retry permanent")
        XCTAssertTrue(p.shouldRetry(afterAttempt: 0, failure: .transient))
        XCTAssertTrue(p.shouldRetry(afterAttempt: 2, failure: .transient))
        XCTAssertFalse(p.shouldRetry(afterAttempt: 3, failure: .transient), "4th attempt is the cap")
    }

    // MARK: - Stall state machine

    func testStallIgnoresStaleGeneration() {
        var m = StallModel(maxConsecutiveSkips: 4)
        let g = m.beginLoad()
        _ = m.beginLoad()                      // a newer load happened
        XCTAssertEqual(m.evaluateStall(generation: g, autoPlay: true), .ignoreStale)
    }

    func testStallHealthyWhenConfirmed() {
        var m = StallModel()
        let g = m.beginLoad()
        m.confirmPlayback(generation: g)
        XCTAssertEqual(m.evaluateStall(generation: g, autoPlay: true), .healthy)
    }

    func testStallReadyPausedIsHealthyOnlyWhenNotAutoplay() {
        var m = StallModel()
        let g = m.beginLoad()
        m.markReady(generation: g)
        XCTAssertEqual(m.evaluateStall(generation: g, autoPlay: false), .healthy,
            "ready-but-paused is fine when we didn't intend to play")
        XCTAssertEqual(m.evaluateStall(generation: g, autoPlay: true), .skip,
            "ready is NOT enough when we wanted audio")
    }

    func testStallGivesUpAfterCapAndResetsOnPlayback() {
        var m = StallModel(maxConsecutiveSkips: 3)
        // Two stalls (each a fresh generation, no audio between) → skip.
        for _ in 0..<2 {
            let g = m.beginLoad()
            XCTAssertEqual(m.evaluateStall(generation: g, autoPlay: true), .skip)
        }
        // Third consecutive stall hits the cap → give up.
        let g3 = m.beginLoad()
        XCTAssertEqual(m.evaluateStall(generation: g3, autoPlay: true), .giveUp)
    }

    func testConfirmedPlaybackResetsSkipStreak() {
        var m = StallModel(maxConsecutiveSkips: 2)
        let g1 = m.beginLoad()
        XCTAssertEqual(m.evaluateStall(generation: g1, autoPlay: true), .skip)  // streak=1
        let g2 = m.beginLoad()
        m.confirmPlayback(generation: g2)                                       // real audio → reset
        let g3 = m.beginLoad()
        XCTAssertEqual(m.evaluateStall(generation: g3, autoPlay: true), .skip,
            "streak reset by playback, so this is a skip not a give-up")
    }

    // MARK: - Source selection

    func testSourcePrefersLocalThenInFlightThenStream() {
        XCTAssertEqual(
            SourceSelector.select(.init(trackID: "a", localCompletePath: "/x.mp3",
                                        downloadInFlight: true, isPerFileURL: false)),
            .localComplete(path: "/x.mp3"))
        XCTAssertEqual(
            SourceSelector.select(.init(trackID: "a", localCompletePath: nil,
                                        downloadInFlight: true, isPerFileURL: false)),
            .joinInFlightDownload(id: "a"), "never double-fetch an in-flight download")
        XCTAssertEqual(
            SourceSelector.select(.init(trackID: "a", localCompletePath: nil,
                                        downloadInFlight: false, isPerFileURL: false)),
            .stream(resolveNeeded: true), "whole-item id needs IA resolve")
        XCTAssertEqual(
            SourceSelector.select(.init(trackID: "id/file.mp3", localCompletePath: nil,
                                        downloadInFlight: false, isPerFileURL: true)),
            .stream(resolveNeeded: false), "per-file id streams directly")
    }

    // MARK: - Throughput estimator

    func testEWMAConverges() {
        var e = ThroughputEstimator(alpha: 0.5)
        e.record(bytes: 100, over: 1)     // 100 B/s
        XCTAssertEqual(e.bytesPerSecond ?? 0, 100, accuracy: 1e-9)
        e.record(bytes: 300, over: 1)     // sample 300; 0.5*300 + 0.5*100 = 200
        XCTAssertEqual(e.bytesPerSecond ?? 0, 200, accuracy: 1e-9)
    }

    func testBestBitratePicksHighestWithinBudget() {
        var e = ThroughputEstimator()
        e.record(bytes: 1_000_000, over: 1)               // 1 MB/s
        // safety 0.8 → budget 800 KB/s. Available in B/s:
        let avail = [64_000.0, 128_000, 320_000, 1_200_000]
        XCTAssertEqual(e.bestBitrate(from: avail, safety: 0.8), 320_000)
        // Unknown throughput → best available.
        let blank = ThroughputEstimator()
        XCTAssertEqual(blank.bestBitrate(from: avail), 1_200_000)
        // None fit → smallest.
        var slow = ThroughputEstimator()
        slow.record(bytes: 10_000, over: 1)
        XCTAssertEqual(slow.bestBitrate(from: avail, safety: 0.8), 64_000)
    }

    func testPrebufferETA() {
        var e = ThroughputEstimator()
        e.record(bytes: 200_000, over: 1)   // 200 KB/s
        // 2 s of audio at 100 KB/s bitrate = 200 KB needed / 200 KB/s = 1 s.
        XCTAssertEqual(e.prebufferETA(seconds: 2, bitrateBytesPerSec: 100_000) ?? -1,
                       1.0, accuracy: 1e-9)
        XCTAssertNil(ThroughputEstimator().prebufferETA(seconds: 2, bitrateBytesPerSec: 100_000),
                     "no estimate yet → nil")
    }

    // MARK: - Cache eviction

    func testEvictionFreesToTargetLRUFirst() {
        let now = Date()
        let entries = [
            CacheEntry(id: "old",  size: 100, lastAccess: now.addingTimeInterval(-300), pinned: false),
            CacheEntry(id: "mid",  size: 100, lastAccess: now.addingTimeInterval(-200), pinned: false),
            CacheEntry(id: "new",  size: 100, lastAccess: now.addingTimeInterval(-100), pinned: false),
        ]
        // total 300, cap 150 → must free ≥150 → evict the 2 LRU (old, mid).
        XCTAssertEqual(CacheEvictionPolicy.evictions(entries, maxBytes: 150), ["old", "mid"])
        // Under cap → nothing.
        XCTAssertEqual(CacheEvictionPolicy.evictions(entries, maxBytes: 500), [])
    }

    // MARK: - Single-flight registry

    func testInFlightRegistrySingleFlight() {
        let r = InFlightRegistry()
        XCTAssertTrue(r.begin("a"),  "first claim succeeds")
        XCTAssertFalse(r.begin("a"), "second concurrent claim is rejected (single-flight)")
        XCTAssertTrue(r.contains("a"))
        XCTAssertFalse(r.contains("b"))
        r.end("a")
        XCTAssertFalse(r.contains("a"))
        XCTAssertTrue(r.begin("a"), "claimable again after it ends")
    }

    func testInFlightRegistryTracksMultipleIDs() {
        let r = InFlightRegistry()
        r.begin("a"); r.begin("b")
        XCTAssertTrue(r.contains("a") && r.contains("b"))
        r.end("a")
        XCTAssertFalse(r.contains("a"))
        XCTAssertTrue(r.contains("b"), "ending one id doesn't affect another")
    }

    func testEvictionNeverTouchesPinned() {
        let now = Date()
        let entries = [
            CacheEntry(id: "pinnedOld", size: 200, lastAccess: now.addingTimeInterval(-999), pinned: true),
            CacheEntry(id: "free",      size: 100, lastAccess: now.addingTimeInterval(-100), pinned: false),
        ]
        // cap 100, total 300. Pinned (200) alone exceeds cap; evict all unpinned only.
        XCTAssertEqual(CacheEvictionPolicy.evictions(entries, maxBytes: 100), ["free"])
    }
}
