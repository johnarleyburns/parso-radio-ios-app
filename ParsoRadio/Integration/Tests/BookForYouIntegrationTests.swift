import XCTest
@testable import ParsoMusic

final class BookForYouIntegrationTests: XCTestCase {

    private var db: DatabaseService!
    private var service: BookForYouService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        service = BookForYouService(db: db)
    }

    override func tearDown() {
        db = nil
        service = nil
        super.tearDown()
    }

    // MARK: - LibriVox Search

    func testSearchLibrivoxGeneralFictionReturnsResults() async throws {
        let query = "collection:librivoxaudio AND subject:\"General Fiction\""
        let components = URLComponents(string: BookForYouService.searchBase)!
        var urlComponents = components
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "creator"),
            URLQueryItem(name: "fl[]", value: "subject"),
            URLQueryItem(name: "fl[]", value: "downloads"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "rows", value: "10"),
            URLQueryItem(name: "sort[]", value: "downloads desc"),
        ]
        let (data, response) = try await URLSession.shared.data(from: urlComponents.url!)

        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Invalid response type")
            return
        }
        XCTAssertEqual(httpResponse.statusCode, 200)

        let decoded = try JSONDecoder().decode(IASearchResponse.self, from: data)
        XCTAssertFalse(decoded.response.docs.isEmpty,
            "LibriVox General Fiction query must return at least one result")
        XCTAssertTrue(decoded.response.docs.count >= 3,
            "LibriVox General Fiction query must return at least 3 results")
    }

    // MARK: - Generate Pick End-to-End

    func testGeneratePickReturnsValidEntry() async {
        let today = BookForYouIntegrationTests.todayKey()
        let entry = await service.generatePick(for: today)

        XCTAssertNotNil(entry, "generatePick must return a valid entry")
        guard let entry else { return }

        XCTAssertFalse(entry.identifier.isEmpty, "Entry must have a non-empty identifier")
        XCTAssertFalse(entry.title.isEmpty, "Entry must have a non-empty title")
        XCTAssertFalse(entry.author.isEmpty, "Entry must have a non-empty author")
        XCTAssertEqual(entry.reason, "Popular on LibriVox",
            "Cold-start entries must have the correct reason string")
    }

    func testGeneratePickCoverURLIsValid() async throws {
        let today = BookForYouIntegrationTests.todayKey()
        guard let entry = await service.generatePick(for: today) else {
            XCTFail("generatePick returned nil")
            return
        }

        let (data, response) = try await URLSession.shared.data(from: entry.coverURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Invalid response type for cover image")
            return
        }
        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertGreaterThan(data.count, 2048,
            "Cover image must be larger than 2KB (IA's default placeholder is <2KB)")
    }

    func testGeneratePickIdentifierHasMetadata() async throws {
        let today = BookForYouIntegrationTests.todayKey()
        guard let entry = await service.generatePick(for: today) else {
            XCTFail("generatePick returned nil")
            return
        }

        let encoded = entry.identifier
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.identifier
        let metaURL = URL(string: "https://archive.org/metadata/\(encoded)")!
        let (data, response) = try await URLSession.shared.data(from: metaURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Invalid response")
            return
        }
        // 429 or 5xx are transient; treat as non-fatal
        if httpResponse.statusCode != 200 {
            print("⚠️ IA metadata returned \(httpResponse.statusCode) — skipping")
            return
        }

        struct IAMeta: Decodable {
            struct F: Decodable { let name: String }
            let files: [F]
        }
        let meta = try JSONDecoder().decode(IAMeta.self, from: data)
        XCTAssertFalse(meta.files.isEmpty,
            "Book identifier \(entry.identifier) must have at least one file in metadata")
    }

    // MARK: - Cold Start Consistency

    func testColdStartAlwaysReturnsGeneralFictionReason() async {
        for _ in 0..<3 {
            // Simulate different days
            let randomDay = String(format: "2025-06-%02d", Int.random(in: 1...28))
            if let entry = await service.generatePick(for: randomDay) {
                // If db has no profile, reason must be cold-start fallback
                XCTAssertEqual(entry.reason, "Popular on LibriVox")
            }
        }
    }

    // MARK: - Helpers

    private static func todayKey() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
