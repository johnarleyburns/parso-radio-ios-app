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

    private func makeSearchJSON(entries: [MockEtreeEntry]) -> String {
        let docs = entries.map { e in
            var parts = [String]()
            parts.append("\"identifier\":\"\(e.identifier)\"")
            parts.append("\"creator\":\"\(e.creator)\"")
            parts.append("\"date\":\"\(e.date)\"")
            parts.append("\"year\":\(e.year)")
            parts.append("\"downloads\":\(e.downloads)")
            let desc = e.description.replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("\"description\":\"\(desc)\"")
            return "{\(parts.joined(separator: ","))}"
        }.joined(separator: ",")
        return "{\"response\":{\"numFound\":\(entries.count),\"start\":0,\"docs\":[\(docs)]}}"
    }

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

    private func mockEtreeResponse(entries: [MockEtreeEntry]) {
        let searchJSON = makeSearchJSON(entries: entries)
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/metadata/") == true {
                let id = request.url!.lastPathComponent
                let metaJSON = self.makeMetadataJSON(
                    id: id, title: "Full Show Title " + id, creator: "Test Band",
                    venue: "Test Venue", coverage: "Test City, ST",
                    date: "2020-06-20", description: "A great show recording."
                )
                let data = metaJSON.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            let data = searchJSON.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
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

    private func mockNetworkError() {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
    }

    private func mockWithMetadata(title: String, creator: String) {
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/metadata/") == true {
                let id = request.url!.lastPathComponent
                let metaJSON = self.makeMetadataJSON(
                    id: id, title: title + id, creator: creator,
                    venue: "Test Venue", coverage: "Test City, ST",
                    date: "2020-06-20", description: "A great show recording."
                )
                let data = metaJSON.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            let data = "{\"response\":{\"numFound\":0,\"start\":0,\"docs\":[]}}".data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
    }

    // MARK: - Tests

    func testDateFilteringExcludesWrongDateEntries() async throws {
        mockEtreeResponse(entries: [
            MockEtreeEntry(identifier: "good-001", creator: "Band A", date: "2020-06-20", year: 2020, downloads: 100, description: "Soundboard \u{2022} Ithaca, NY \u{2022} Barton Hall"),
            MockEtreeEntry(identifier: "bad-001", creator: "Band B", date: "2020-07-04", year: 2020, downloads: 200, description: "Soundboard \u{2022} SF \u{2022} Fillmore"),
        ])

        let service = LiveMusicOnThisDayService(session: session)
        let entries = try await service.fetchEntries(for: "06-20")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "good-001")
    }

    func testTitlelessEntriesAreSkipped() async throws {
        let searchJSON = "{\"response\":{\"numFound\":1,\"start\":0,\"docs\":[{\"identifier\":\"notitle-001\",\"creator\":\"Band A\",\"date\":\"2020-06-20\",\"year\":2020,\"downloads\":100,\"description\":\"Soundboard \u{2022} City \u{2022} Venue A\"}]}}"
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/metadata/") == true {
                let metaJSON = "{\"metadata\":{\"creator\":\"Band A\",\"venue\":\"Venue A\",\"date\":\"2020-06-20\"}}"
                let data = metaJSON.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            let data = searchJSON.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = LiveMusicOnThisDayService(session: session)
        let result = await service.fetchDailyEntry()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.displayName, "Band A")
    }

    func testCachePoolRoundtrip() async throws {
        mockEtreeResponse(entries: [
            MockEtreeEntry(identifier: "gd-001", creator: "Grateful Dead", date: "2020-06-20", year: 2020, downloads: 500, description: "Soundboard \u{2022} CA \u{2022} Fillmore"),
        ])

        let service = LiveMusicOnThisDayService(session: session)
        let entry = await service.fetchDailyEntry()
        XCTAssertNotNil(entry)

        let data = UserDefaults.standard.data(forKey: "liveMusicPool_06-20")
        XCTAssertNotNil(data)
        let decoded = try JSONDecoder().decode([LiveMusicEntry].self, from: data!)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, "gd-001")

        let poolDate = UserDefaults.standard.double(forKey: "liveMusicPoolDate_06-20")
        XCTAssertGreaterThan(poolDate, 0)

        let cachedDate = Date(timeIntervalSince1970: poolDate)
        XCTAssertTrue(Calendar.current.isDate(cachedDate, inSameDayAs: Date()))
    }

    func testMetadataEnrichmentMergesFields() async throws {
        let searchJSON = "{\"response\":{\"numFound\":1,\"start\":0,\"docs\":[{\"identifier\":\"enrich-001\",\"creator\":\"Raw Creator\",\"date\":\"2020-06-20\",\"year\":2020,\"downloads\":50,\"description\":\"Soundboard \u{2022} City \u{2022} The Venue\"}]}}"
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/metadata/") == true {
                let metaJSON = self.makeMetadataJSON(
                    id: "enrich-001", title: "Full Show Title enrich-001", creator: "Test Band",
                    venue: "Test Venue", coverage: "Test City, ST",
                    date: "2020-06-20", description: "A great show recording."
                )
                let data = metaJSON.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            let data = searchJSON.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = LiveMusicOnThisDayService(session: session)
        let result = await service.fetchDailyEntry()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "enrich-001")
        XCTAssertEqual(result?.title, "Full Show Title enrich-001")
        XCTAssertEqual(result?.creator, "Test Band")
        XCTAssertEqual(result?.venue, "Test Venue")
        XCTAssertEqual(result?.coverage, "Test City, ST")
        XCTAssertEqual(result?.description, "A great show recording.")
    }

    func testNetworkErrorExpiresCache() async throws {
        mockEtreeResponse(entries: [
            MockEtreeEntry(identifier: "cache-001", creator: "Test Band", date: "2020-06-20", year: 2020, downloads: 10, description: "Soundboard \u{2022} City \u{2022} Venue"),
        ])
        let serviceA = LiveMusicOnThisDayService(session: session)
        let entryA = await serviceA.fetchDailyEntry()
        XCTAssertNotNil(entryA)

        let cachedData = UserDefaults.standard.data(forKey: "liveMusicPool_06-20")
        XCTAssertNotNil(cachedData)

        serviceA.clearCachedEntry()
        mockNetworkError()
        let serviceB = LiveMusicOnThisDayService(session: session)
        let entryB = await serviceB.fetchDailyEntry()
        XCTAssertNil(entryB)

        let poolData = UserDefaults.standard.data(forKey: "liveMusicPool_06-20")
        XCTAssertNil(poolData)
        let poolDate = UserDefaults.standard.double(forKey: "liveMusicPoolDate_06-20")
        XCTAssertEqual(poolDate, 0)
    }

    func testForceFreshAvoidsRepeatEntry() async throws {
        let searchJSON = "{\"response\":{\"numFound\":2,\"start\":0,\"docs\":[{\"identifier\":\"entry-001\",\"creator\":\"Band A\",\"date\":\"2020-06-20\",\"year\":2020,\"downloads\":100,\"description\":\"Soundboard \u{2022} City \u{2022} Venue A\"},{\"identifier\":\"entry-002\",\"creator\":\"Band B\",\"date\":\"2020-06-20\",\"year\":2020,\"downloads\":200,\"description\":\"Soundboard \u{2022} City \u{2022} Venue B\"}]}}"
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/metadata/") == true {
                let id = request.url!.lastPathComponent
                let metaJSON = self.makeMetadataJSON(
                    id: id, title: "Full Show " + id, creator: "Test Band",
                    venue: "Venue", coverage: "", date: "2020-06-20",
                    description: "A great show."
                )
                let data = metaJSON.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            let data = searchJSON.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = LiveMusicOnThisDayService(session: session)
        let first = await service.fetchDailyEntry()
        XCTAssertNotNil(first)

        let second = await service.fetchDailyEntry(forceFresh: true)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.id, second?.id)
    }

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

    func testForceFreshAvoidsLastPickedAcrossInstances() async throws {
        let searchJSON = "{\"response\":{\"numFound\":3,\"start\":0,\"docs\":[{\"identifier\":\"entry-a\",\"creator\":\"Band A\",\"date\":\"2020-06-20\",\"year\":2020,\"downloads\":100,\"description\":\"Soundboard \u{2022} City \u{2022} Venue A\"},{\"identifier\":\"entry-b\",\"creator\":\"Band B\",\"date\":\"2020-06-20\",\"year\":2020,\"downloads\":200,\"description\":\"Soundboard \u{2022} City \u{2022} Venue B\"},{\"identifier\":\"entry-c\",\"creator\":\"Band C\",\"date\":\"2020-06-20\",\"year\":2020,\"downloads\":300,\"description\":\"Soundboard \u{2022} City \u{2022} Venue C\"}]}}"
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/metadata/") == true {
                let id = request.url!.lastPathComponent
                let metaJSON = self.makeMetadataJSON(
                    id: id, title: "Full Show " + id, creator: "Test Band",
                    venue: "Venue", coverage: "", date: "2020-06-20",
                    description: "A great show."
                )
                let data = metaJSON.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            let data = searchJSON.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        // First service instance picks an entry
        let serviceA = LiveMusicOnThisDayService(session: session)
        let first = await serviceA.fetchDailyEntry()
        XCTAssertNotNil(first)

        // Second service instance with forceFresh should avoid first
        let serviceB = LiveMusicOnThisDayService(session: session)
        let second = await serviceB.fetchDailyEntry(forceFresh: true)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.id, second?.id,
            "forceFresh across instances must avoid the last picked entry via UserDefaults")
    }

    func testRefreshFromPoolDoesNotClearCache() async throws {
        mockEtreeResponse(entries: [
            MockEtreeEntry(identifier: "rpool-001", creator: "Test Band", date: "2020-06-20", year: 2020, downloads: 10, description: "Soundboard \u{2022} City \u{2022} Venue"),
        ])

        let serviceA = LiveMusicOnThisDayService(session: session)
        _ = await serviceA.fetchDailyEntry()

        let poolData = UserDefaults.standard.data(forKey: "liveMusicPool_06-20")
        XCTAssertNotNil(poolData, "Pool must be cached after first fetch")

        // Simulate refreshFromPool: new instance, forceFresh, no clearCache
        let serviceB = LiveMusicOnThisDayService(session: session)
        let entry = await serviceB.fetchDailyEntry(forceFresh: true)
        XCTAssertNotNil(entry, "refreshFromPool must still return an entry")

        let poolAfter = UserDefaults.standard.data(forKey: "liveMusicPool_06-20")
        XCTAssertNotNil(poolAfter, "Pool must remain after refreshFromPool (no clearCache called)")
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
