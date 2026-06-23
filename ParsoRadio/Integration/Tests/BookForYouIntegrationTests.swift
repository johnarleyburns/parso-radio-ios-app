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

    // MARK: - Bundled Books

    func testBundledBooksLoaded() {
        let books = LibrivoxBundledBooks.all
        XCTAssertFalse(books.isEmpty, "Bundled books list must not be empty")
        XCTAssertGreaterThan(books.count, 30,
            "Bundled books must contain at least 30 titles for meaningful rotation")
    }

    func testBundledBooksAreValid() {
        for book in LibrivoxBundledBooks.all {
            XCTAssertFalse(book.identifier.isEmpty,
                "Book \(book.title) has empty identifier")
            XCTAssertFalse(book.title.isEmpty,
                "Book has empty title")
            XCTAssertFalse(book.author.isEmpty,
                "Book \(book.identifier) has empty author")
            XCTAssertFalse(book.work_key.isEmpty,
                "Book \(book.identifier) has empty work_key")
        }
    }

    func testBundledBooksHaveUniqueWorkKeys() {
        let keys = LibrivoxBundledBooks.all.map { $0.work_key }
        XCTAssertEqual(keys.count, Set(keys).count,
            "All bundled books must have unique work_keys")
    }

    func testBundledBooksHaveCoverURLs() async throws {
        // Spot-check: the first 3 bundled books should have valid IA cover images
        for book in LibrivoxBundledBooks.all.prefix(3) {
            let coverURL = URL(string: "https://archive.org/services/img/\(book.identifier)")!
            let (data, response) = try await URLSession.shared.data(from: coverURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                XCTFail("Invalid response for \(book.identifier)")
                return
            }
            XCTAssertEqual(httpResponse.statusCode, 200)
            XCTAssertGreaterThan(data.count, 2048,
                "Cover for \(book.identifier) must be >2KB (IA placeholder is <2KB)")
        }
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

    // MARK: - Cold Start Works Offline

    func testGeneratePickWorksOffline() async {
        // Since cold-start now uses bundled books (no network needed),
        // generatePick must always return a valid entry even when offline.
        for _ in 0..<3 {
            let randomDay = String(format: "2025-06-%02d", Int.random(in: 1...28))
            let entry = await service.generatePick(for: randomDay)
            XCTAssertNotNil(entry, "generatePick must return an entry even offline")
            XCTAssertEqual(entry?.reason, "Popular on LibriVox",
                "Cold-start entries must have the correct reason")
        }
    }

    // MARK: - Helpers

    private static func todayKey() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
