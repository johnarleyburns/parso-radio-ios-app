import XCTest
@testable import ParsoMusic

final class FeaturedPickerTests: XCTestCase {
    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }

    func testDeterministicWithinADay() {
        XCTAssertEqual(FeaturedPicker.featured(on: day("2026-06-20")).map(\.id),
                       FeaturedPicker.featured(on: day("2026-06-20")).map(\.id))
        XCTAssertEqual(FeaturedPicker.hero(on: day("2026-06-20"))?.id,
                       FeaturedPicker.hero(on: day("2026-06-20"))?.id)
    }

    func testRotatesAcrossDays() {
        let heroes = (0..<14).map { FeaturedPicker.hero(on: day("2026-06-\(String(format: "%02d", $0 + 1))"))?.id }
        XCTAssertGreaterThan(Set(heroes.compactMap { $0 }).count, 1, "Hero should rotate over two weeks")
    }

    func testNeverReturnsForYou() {
        XCTAssertFalse(FeaturedPicker.featured(on: day("2026-06-20")).contains { $0.category == "For You" })
        XCTAssertNotEqual(FeaturedPicker.hero(on: day("2026-06-20"))?.category, "For You")
    }

    func testFeaturedSpansAvailableKinds() {
        let kinds = Set(FeaturedPicker.featured(on: day("2026-06-20")).map(\.mediaKind))
        XCTAssertGreaterThanOrEqual(kinds.count, 2, "Featured shelf should mix media kinds")
    }
}
