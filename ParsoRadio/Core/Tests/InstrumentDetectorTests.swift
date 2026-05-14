import XCTest
@testable import ParsoMusic

final class InstrumentDetectorTests: XCTestCase {
    private let detector = InstrumentDetector()

    func testDetectsStringsFromTitle() {
        let result = detector.detect(title: "Brandenburg Concerto No. 3", subjects: [], description: nil)
        XCTAssertTrue(result.contains("strings"))
    }

    func testDetectsPianoFromTitle() {
        let result = detector.detect(title: "Nocturne Op. 9 No. 2", subjects: [], description: nil)
        XCTAssertTrue(result.contains("piano"))
    }

    func testDetectsStringsFromSubject() {
        let result = detector.detect(title: "Concerto", subjects: ["violin", "orchestra"], description: nil)
        XCTAssertTrue(result.contains("strings"))
    }

    func testEmptyInputReturnsEmpty() {
        let result = detector.detect(title: "", subjects: [], description: nil)
        XCTAssertTrue(result.isEmpty)
    }

    func testSonataAloneDoesNotImplyPiano() {
        let result = detector.detect(title: "Violin Sonata in G", subjects: [], description: nil)
        XCTAssertFalse(result.contains("piano"))
        XCTAssertTrue(result.contains("strings"))
    }

    func testTrackCanHaveBothInstruments() {
        let result = detector.detect(
            title: "Piano and Violin Sonata",
            subjects: [],
            description: nil
        )
        XCTAssertTrue(result.contains("piano"))
        XCTAssertTrue(result.contains("strings"))
    }
}
