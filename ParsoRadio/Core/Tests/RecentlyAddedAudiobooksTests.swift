import XCTest
@testable import ParsoMusic

final class RecentlyAddedAudiobooksTests: XCTestCase {
    private var service: RecentlyAddedAudiobooksService!
    private var config: URLSessionConfiguration!

    override func setUp() {
        super.setUp()
        config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        service = RecentlyAddedAudiobooksService(session: URLSession(configuration: config))
        service.clearCachedEntry()
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        service.clearCachedEntry()
        service = nil
        super.tearDown()
    }

    private func mockIA(identifiers: [String]) {
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/metadata/") == true {
                // Metadata enrichment — return minimal valid response
                let ident = request.url!.lastPathComponent
                let json = """
                {"metadata":{"identifier":"\(ident)","title":"\(ident)","creator":"Author"}}
                """
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }
            // Search response
            let docs = identifiers.map { id in
                #"{"identifier":"\#(id)","title":"\#(id)","creator":"Author","downloads":100}"#
            }.joined(separator: ",")
            let json = #"{"response":{"docs":[\#(docs)]}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
    }

    // MARK: - Fresh pick yields different entries

    func testForceFreshPicksDifferentEntry() async {
        mockIA(identifiers: ["a", "b", "c", "d", "e"])

        // First fetch (no prior state)
        let first = await service.fetchDailyEntry(forceFresh: true)
        XCTAssertNotNil(first)

        // Second fetch with forceFresh should skip the first ID
        let second = await service.fetchDailyEntry(forceFresh: true)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.id, second?.id, "forceFresh should pick a different entry")

        // Third fetch should skip the second ID
        let third = await service.fetchDailyEntry(forceFresh: true)
        XCTAssertNotNil(third)
        XCTAssertNotEqual(second?.id, third?.id, "forceFresh should pick a different entry again")
    }

    func testForceFreshAvoidsLastPickWhenMultipleAvailable() async {
        // With 3 entries, each forceFresh call should skip the immediately previous ID.
        // Two consecutive calls should ALWAYS produce different results when >1 entry.
        mockIA(identifiers: ["x", "y", "z"])
        let first = await service.fetchDailyEntry(forceFresh: true)
        let second = await service.fetchDailyEntry(forceFresh: true)
        XCTAssertNotEqual(first?.id, second?.id, "forceFresh should pick different from previous")
    }

    func testForceFreshFallsBackWhenOnlyOneEntry() async {
        mockIA(identifiers: ["only-one"])
        let first = await service.fetchDailyEntry(forceFresh: true)
        let second = await service.fetchDailyEntry(forceFresh: true)
        // With only 1 entry, both should return it
        XCTAssertEqual(first?.id, "only-one")
        XCTAssertEqual(second?.id, "only-one")
    }

    func testFetchWithoutForceFreshReturnsCached() async {
        mockIA(identifiers: ["cached-book"])
        let first = await service.fetchDailyEntry()
        XCTAssertNotNil(first)

        // Without forceFresh, should return the cached entry
        let second = await service.fetchDailyEntry(forceFresh: false)
        XCTAssertEqual(first?.id, second?.id)
    }

    func testReturnsNilWhenNoResults() async {
        mockIA(identifiers: [])
        let entry = await service.fetchDailyEntry(forceFresh: true)
        XCTAssertNil(entry)
    }

    // MARK: - Robust JSON decoding

    func testDecodeHandlesStringDownloadsAndArrayCreator() async {
        // Simulate IA returning downloads as String and creator as array
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/metadata/") == true {
                let ident = request.url!.lastPathComponent
                let json = """
                {"metadata":{"identifier":"\(ident)","title":"\(ident)","creator":"Author Name"}}
                """
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }
            let json = """
            {"response":{"docs":[{"identifier":"book1","title":"Test Book","creator":["Author Name"],"downloads":"1000"}]}}
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let entry = await service.fetchDailyEntry(forceFresh: true)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.id, "book1")
        XCTAssertEqual(entry?.creator, "Author Name")
    }
}
