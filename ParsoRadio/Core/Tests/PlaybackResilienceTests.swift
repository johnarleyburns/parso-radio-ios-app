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

}
