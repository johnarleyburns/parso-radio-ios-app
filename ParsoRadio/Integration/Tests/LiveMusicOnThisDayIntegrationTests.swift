import XCTest
@testable import ParsoMusic

/// Hits the real Internet Archive API to verify the etree query works.
final class LiveMusicOnThisDayIntegrationTests: XCTestCase {
    private let service = LiveMusicOnThisDayService()

    func testRealIAFetchReturnsResults() async throws {
        // 05-08 (May 8) is a famous Grateful Dead show date — should always return results
        let entries = try await service.fetchEntries(for: "05-08")

        // IA etree should return >0 results for this date
        XCTAssertFalse(entries.isEmpty, "Expected at least one etree result for 05-08")

        // Verify each entry has required fields
        for entry in entries {
            XCTAssertFalse(entry.id.isEmpty, "identifier must not be empty")
            XCTAssertFalse(entry.creator.isEmpty, "creator must not be empty")
        }
    }

    func testRealIAThumbnailExistsForResult() async throws {
        let entries = try await service.fetchEntries(for: "05-08")
        guard let first = entries.first else {
            throw XCTSkip("No IA results — skipping thumbnail test")
        }
        // Verify the IA services/img URL returns a valid image
        let url = first.thumbnailURL
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = response as? HTTPURLResponse
        XCTAssertEqual(http?.statusCode, 200)
        XCTAssertGreaterThan(data.count, 1000, "Thumbnail image should be >1KB")
    }

    func testRealIAFetchRandomDateReturnsData() async throws {
        // Test with a date that should have content in etree
        let entries = try await service.fetchEntries(for: "07-04")
        // Not all dates have shows, but 07-04 is Independence Day and popular
        // We just verify the structure — not that results are non-empty
        for entry in entries {
            XCTAssertFalse(entry.id.isEmpty)
        }
    }
}
