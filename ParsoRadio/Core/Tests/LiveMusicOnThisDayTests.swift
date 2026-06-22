import XCTest
@testable import ParsoMusic

final class LiveMusicOnThisDayTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        UserDefaults.standard.removeObject(forKey: "liveMusicPool_06-20")
        UserDefaults.standard.removeObject(forKey: "liveMusicPoolDate_06-20")
        UserDefaults.standard.removeObject(forKey: "liveMusicEntry_06-20")
        UserDefaults.standard.removeObject(forKey: "liveMusicLastPicked_06-20")
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        UserDefaults.standard.removeObject(forKey: "liveMusicPool_06-20")
        UserDefaults.standard.removeObject(forKey: "liveMusicPoolDate_06-20")
        UserDefaults.standard.removeObject(forKey: "liveMusicEntry_06-20")
        UserDefaults.standard.removeObject(forKey: "liveMusicLastPicked_06-20")
        super.tearDown()
    }

    // MARK: - Mock helpers

    private func makeMetadataJSON(id: String, title: String, creator: String, venue: String, coverage: String, date: String, description: String) -> String {
        let fields: [(String, String)] = [
            ("title", title), ("creator", creator), ("venue", venue),
            ("coverage", coverage), ("date", date), ("description", description)
        ]
        let meta = fields.map { k, v in
            let escaped = v.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(k)\":\"\(escaped)\""
        }.joined(separator: ",")
        return "{\"metadata\":{\(meta)}}"
    }

    private func mockEmptyEtreeResponse() {
        let json = "{\"response\":{\"numFound\":0,\"start\":0,\"docs\":[]}}"
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/metadata/") == true {
                let metaJSON = self.makeMetadataJSON(
                    id: request.url!.lastPathComponent, title: "irrelevant", creator: "irrelevant",
                    venue: "", coverage: "", date: "", description: ""
                )
                let data = metaJSON.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
    }

    // MARK: - Tests

    func testEntryDecodingFromRealFormat() throws {
        let json = "{\"response\":{\"numFound\":1,\"start\":0,\"docs\":[{\"identifier\":\"gd1977-05-08\",\"creator\":\"Grateful Dead\",\"date\":\"1977-05-08T00:00:00Z\",\"year\":1977,\"downloads\":45000,\"description\":\"Soundboard \u{2022} Ithaca, NY \u{2022} Barton Hall\"}]}}"
        let data = json.data(using: .utf8)!
        struct Envelope: Decodable { let response: Resp }
        struct Resp: Decodable { let docs: [LiveMusicOnThisDayTests.MockEtreeEntry] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        XCTAssertEqual(envelope.response.docs.count, 1)
        XCTAssertEqual(envelope.response.docs[0].identifier, "gd1977-05-08")
        XCTAssertEqual(envelope.response.docs[0].creator, "Grateful Dead")
        XCTAssertEqual(envelope.response.docs[0].year, 1977)
        XCTAssertEqual(envelope.response.docs[0].downloads, 45000)
    }

    func testEmptyPoolReturnsNil() async {
        mockEmptyEtreeResponse()
        let service = LiveMusicOnThisDayService(session: session)
        let result = await service.fetchDailyEntry()
        XCTAssertNil(result)
    }

    func testThumbnailURLFormat() {
        let entry = LiveMusicEntry(
            id: "gd1977-05-08",
            creator: "Grateful Dead",
            dateString: "06-20"
        )
        XCTAssertEqual(entry.thumbnailURL.absoluteString, "https://archive.org/services/img/gd1977-05-08")
    }

    func testDisplayNameFallsBackToCreator() {
        let entryWithTitle = LiveMusicEntry(
            id: "test-001",
            creator: "Test Band",
            title: "Full Show Title",
            dateString: "06-20"
        )
        XCTAssertEqual(entryWithTitle.displayName, "Full Show Title")

        let entryWithoutTitle = LiveMusicEntry(
            id: "test-002",
            creator: "Only Band",
            dateString: "06-20"
        )
        XCTAssertEqual(entryWithoutTitle.displayName, "Only Band")
    }

    func testFormattedDateParsing() {
        let entry = LiveMusicEntry(
            id: "test-001",
            creator: "Test Band",
            date: "2023-06-09T00:00:00Z",
            dateString: "06-09"
        )
        XCTAssertEqual(entry.formattedDate, "June 9, 2023")
    }

    func testLocationSummaryFormatting() {
        let both = LiveMusicEntry(
            id: "test-001",
            creator: "Test Band",
            venue: "Madison Square Garden",
            coverage: "New York, NY",
            dateString: "06-20"
        )
        XCTAssertEqual(both.locationSummary, "Madison Square Garden — New York, NY")

        let venueOnly = LiveMusicEntry(
            id: "test-002",
            creator: "Test Band",
            venue: "The Fillmore",
            dateString: "06-20"
        )
        XCTAssertEqual(venueOnly.locationSummary, "The Fillmore")

        let coverageOnly = LiveMusicEntry(
            id: "test-003",
            creator: "Test Band",
            coverage: "San Francisco, CA",
            dateString: "06-20"
        )
        XCTAssertEqual(coverageOnly.locationSummary, "San Francisco, CA")

        let neither = LiveMusicEntry(
            id: "test-004",
            creator: "Test Band",
            dateString: "06-20"
        )
        XCTAssertNil(neither.locationSummary)
    }

    func testHasTitleComputedProperty() {
        let withTitle = LiveMusicEntry(
            id: "test-001",
            creator: "Band",
            title: "Show Title",
            dateString: "06-20"
        )
        XCTAssertTrue(withTitle.hasTitle)

        let withoutTitle = LiveMusicEntry(
            id: "test-002",
            creator: "Band",
            dateString: "06-20"
        )
        XCTAssertFalse(withoutTitle.hasTitle)
    }

}


// MARK: - Mock models for testing

extension LiveMusicOnThisDayTests {
    struct MockEtreeEntry: Codable {
        let identifier: String
        let creator: String
        let date: String
        let year: Int
        let downloads: Int
        let description: String
    }
}
