import XCTest
@testable import ParsoMusic

// "Curate down" (ASSESSMENT #3): IA download count → a 0.1…1.0 quality weight
// that QueueManager.selectionWeight multiplies, so well-loved recordings surface
// more often without hard-removing the obscure ones.
final class IAQualityScoreTests: XCTestCase {

    func testNilOrZeroDownloadsFloorAtMinimum() {
        XCTAssertEqual(IAQualityScore.fromDownloads(nil), 0.1, accuracy: 1e-9)
        XCTAssertEqual(IAQualityScore.fromDownloads(0), 0.1, accuracy: 1e-9)
    }

    func testMonotonicallyIncreasing() {
        let low  = IAQualityScore.fromDownloads(50)
        let mid  = IAQualityScore.fromDownloads(5_000)
        let high = IAQualityScore.fromDownloads(200_000)
        XCTAssertLessThan(low, mid)
        XCTAssertLessThan(mid, high)
    }

    func testStaysWithinBounds() {
        XCTAssertGreaterThanOrEqual(IAQualityScore.fromDownloads(1), 0.1)
        XCTAssertLessThanOrEqual(IAQualityScore.fromDownloads(10_000_000), 1.0)
    }

    func testAmateurWeightsWellBelowPopular() {
        // A ~50-download amateur upload should weight clearly under a
        // ~100k-download favourite, so weighted selection prefers the latter.
        let amateur = IAQualityScore.fromDownloads(50)
        let popular = IAQualityScore.fromDownloads(100_000)
        XCTAssertLessThan(amateur, popular * 0.6)
    }
}
