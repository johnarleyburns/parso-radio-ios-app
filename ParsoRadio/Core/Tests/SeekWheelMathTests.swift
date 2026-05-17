import XCTest
@testable import ParsoMusic

final class SeekWheelMathTests: XCTestCase {

    // MARK: clockwiseDelta

    func test_clockwiseDelta_clockwise_noWrap() {
        XCTAssertEqual(clockwiseDelta(from: 0, to: .pi / 2), .pi / 2, accuracy: 0.001)
    }

    func test_clockwiseDelta_counterClockwise_noWrap() {
        XCTAssertEqual(clockwiseDelta(from: .pi / 2, to: 0), -.pi / 2, accuracy: 0.001)
    }

    func test_clockwiseDelta_wrapsCorrectly_nearPositivePi() {
        XCTAssertEqual(clockwiseDelta(from: 350 * .pi / 180, to: 10 * .pi / 180),
                       20 * .pi / 180, accuracy: 0.001)
    }

    func test_clockwiseDelta_wrapsCorrectly_nearNegativePi() {
        XCTAssertEqual(clockwiseDelta(from: 10 * .pi / 180, to: 350 * .pi / 180),
                       -20 * .pi / 180, accuracy: 0.001)
    }

    func test_clockwiseDelta_zeroWhenSameAngle() {
        XCTAssertEqual(clockwiseDelta(from: 1.5, to: 1.5), 0, accuracy: 0.001)
    }

    // MARK: angle(from:to:)

    func test_angle_east_isZero() {
        XCTAssertEqual(angle(from: .zero, to: CGPoint(x: 1, y: 0)), 0, accuracy: 0.001)
    }

    func test_angle_south_isHalfPi() {
        XCTAssertEqual(angle(from: .zero, to: CGPoint(x: 0, y: 1)), .pi / 2, accuracy: 0.001)
    }

    func test_angle_west_isPlusMinusPi() {
        XCTAssertEqual(abs(angle(from: .zero, to: CGPoint(x: -1, y: 0))), .pi, accuracy: 0.001)
    }

    func test_angle_north_isNegativeHalfPi() {
        XCTAssertEqual(angle(from: .zero, to: CGPoint(x: 0, y: -1)), -.pi / 2, accuracy: 0.001)
    }

    // MARK: angle(for:duration:)

    func test_angleForTime_zeroTime_is12oClock() {
        XCTAssertEqual(angle(for: 0, duration: 3600), -.pi / 2, accuracy: 0.001)
    }

    func test_angleForTime_fullDuration_completesCircle() {
        XCTAssertEqual(angle(for: 3600, duration: 3600), 3 * .pi / 2, accuracy: 0.001)
    }

    func test_angleForTime_halfDuration_is6oClock() {
        XCTAssertEqual(angle(for: 1800, duration: 3600), .pi / 2, accuracy: 0.001)
    }

    func test_angleForTime_clampsAboveDuration() {
        XCTAssertEqual(angle(for: 3600, duration: 3600),
                       angle(for: 9999, duration: 3600), accuracy: 0.001)
    }

    func test_angleForTime_clampsBelowZero() {
        XCTAssertEqual(angle(for: 0, duration: 3600),
                       angle(for: -999, duration: 3600), accuracy: 0.001)
    }

    func test_angleForTime_zeroDuration_returnsStart() {
        XCTAssertEqual(angle(for: 100, duration: 0), -.pi / 2, accuracy: 0.001)
    }

    // MARK: seekRate

    func test_seekRate_slowDrag_isFinegrained() {
        let secondsPerFullRotation = seekRate(for: 0.5, duration: 3600) * 2 * .pi
        XCTAssertLessThan(secondsPerFullRotation, 600)
    }

    func test_seekRate_fastDrag_isCoarse() {
        let secondsPerFullRotation = seekRate(for: 10.0, duration: 3600) * 2 * .pi
        XCTAssertGreaterThan(secondsPerFullRotation, 600)
    }

    func test_seekRate_scalesWithDuration_longTrack() {
        XCTAssertGreaterThan(seekRate(for: 5.0, duration: 7200),
                             seekRate(for: 5.0, duration: 300))
    }

    func test_seekRate_minimumOf1Second_forVeryShortTracks() {
        XCTAssertGreaterThanOrEqual(seekRate(for: 0.1, duration: 10), 1.0)
    }
}
