import XCTest
@testable import ParsoMusic

final class LiveMusicOnThisDayTests: XCTestCase {
    private var service: LiveMusicOnThisDayService!
    private var config: URLSessionConfiguration!

    override func setUp() {
        super.setUp()
        config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        service = LiveMusicOnThisDayService(session: URLSession(configuration: config))
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        service.clearCachedEntry()
        service = nil
        super.tearDown()
    }

    // MARK: - Query

    func testFetchEntriesReturnsParsedResults() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = #"{"response":{"docs":[{"identifier":"gd1977-05-08.sbd.miller.12345","creator":"Grateful Dead","date":"1977-05-08","year":1977,"downloads":50000,"description":"Grateful Dead • 1977-05-08 • Barton Hall, Ithaca, NY • SBD"}]}}"#
            return (HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let entries = try await service.fetchEntries(for: "05-08")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "gd1977-05-08.sbd.miller.12345")
        XCTAssertEqual(entries[0].creator, "Grateful Dead")
        XCTAssertEqual(entries[0].venue, "Barton Hall, Ithaca, NY")
    }

    func testFetchEntriesEmptyResults() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = #"{"response":{"docs":[]}}"#
            return (HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let entries = try await service.fetchEntries(for: "12-31")
        XCTAssertTrue(entries.isEmpty)
    }

    func testFetchEntriesHandlesMissingVenue() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = #"{"response":{"docs":[{"identifier":"test123","creator":"Test Artist","downloads":100}]}}"#
            return (HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let entries = try await service.fetchEntries(for: "06-01")
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].venue)
    }

    func testFetchEntriesNetworkError() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await service.fetchEntries(for: "01-01")
            XCTFail("Expected error")
        } catch {
            // Expected
        }
    }

    // MARK: - Cache

    func testCacheRoundtrip() async throws {
        service.clearCachedEntry()
        let todayMMDD = LiveMusicOnThisDayService.todayMMDD()
        let mockDate = "2024-\(todayMMDD)"
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"response":{"docs":[{"identifier":"gd1977-05-08.sbd.miller.12345","creator":"Grateful Dead","date":"\(mockDate)","year":1977,"downloads":50000,"description":"Grateful Dead • 1977-05-08 • Barton Hall, Ithaca, NY • SBD"}]}}
            """
            return (HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let first = await service.fetchDailyEntry()
        XCTAssertNotNil(first, "First fetch should succeed when network is available")
        XCTAssertEqual(first?.id, "gd1977-05-08.sbd.miller.12345")

        // Verify the pool was cached in UserDefaults
        let today = LiveMusicOnThisDayService.todayKey()
        let poolKey = "liveMusicPool_" + today
        XCTAssertNotNil(UserDefaults.standard.data(forKey: poolKey), "Pool should be cached after first fetch")

        // Second call should return cached without hitting network
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let cached = await service.fetchDailyEntry()
        XCTAssertNotNil(cached, "Should return cached entry even when network is unavailable")
        XCTAssertEqual(cached?.id, "gd1977-05-08.sbd.miller.12345")
    }

    func testClearCache() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = #"{"response":{"docs":[{"identifier":"test","creator":"Test","date":"1999-12-31","year":1999,"downloads":1}]}}"#
            return (HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let _ = await service.fetchDailyEntry()
        service.clearCachedEntry()
        XCTAssertNil(UserDefaults.standard.data(forKey: "liveMusicEntry_\(LiveMusicOnThisDayService.todayKey())"))
    }

    // MARK: - Entry model

    func testEntryThumbnailURL() {
        let entry = LiveMusicEntry(id: "gd1977-05-08.sbd.miller.12345", creator: "GD", title: "Live at Cornell", venue: nil, coverage: nil, date: "1977-05-08", year: 1977, downloads: 100, dateString: "05-08", description: nil)
        XCTAssertEqual(entry.thumbnailURL.absoluteString, "https://archive.org/services/img/gd1977-05-08.sbd.miller.12345")
    }

    func testEntryDisplayNamePrefersTitle() {
        let entry = LiveMusicEntry(id: "id1", creator: "Grateful Dead", title: "Cornell 77", venue: nil, coverage: nil, date: "1977-05-08", year: 1977, downloads: 1, dateString: "05-08", description: nil)
        XCTAssertEqual(entry.displayName, "Cornell 77")
    }

    func testEntryDisplayNameFallsBackToCreator() {
        let entry = LiveMusicEntry(id: "id1", creator: "Grateful Dead", title: nil, venue: nil, coverage: nil, date: nil, year: nil, downloads: 1, dateString: "01-01", description: nil)
        XCTAssertEqual(entry.displayName, "Grateful Dead")
    }

    func testEntryDisplayNameWithEmptyCreator() {
        let entry = LiveMusicEntry(id: "id1", creator: "", title: nil, venue: nil, coverage: nil, date: nil, year: nil, downloads: 1, dateString: "01-01", description: nil)
        // displayName falls back to creator when title is nil; empty creator is pathological
        // but must not crash — the UI should show an empty string rather than crash
        XCTAssertEqual(entry.displayName, "")
    }

    func testEntryDisplayNameWithEmptyCreatorAndTitle() {
        let entry = LiveMusicEntry(id: "id1", creator: "", title: "Cornell 77", venue: nil, coverage: nil, date: nil, year: nil, downloads: 1, dateString: "01-01", description: nil)
        // title takes precedence over creator
        XCTAssertEqual(entry.displayName, "Cornell 77")
    }

    func testFormattedDate() {
        let entry = LiveMusicEntry(id: "id1", creator: "Test", title: nil, venue: nil, coverage: nil, date: "2023-06-09", year: 2023, downloads: 1, dateString: "06-09", description: nil)
        XCTAssertEqual(entry.formattedDate, "June 9, 2023")
    }

    func testFormattedDateNil() {
        let entry = LiveMusicEntry(id: "id1", creator: "Test", title: nil, venue: nil, coverage: nil, date: nil, year: nil, downloads: 1, dateString: "01-01", description: nil)
        XCTAssertNil(entry.formattedDate)
    }

    func testLocationSummaryWithBoth() {
        let entry = LiveMusicEntry(id: "id1", creator: "T", title: nil, venue: "The Fillmore", coverage: "San Francisco, CA", date: nil, year: nil, downloads: 1, dateString: "01-01", description: nil)
        XCTAssertEqual(entry.locationSummary, "The Fillmore — San Francisco, CA")
    }

    func testLocationSummaryVenueOnly() {
        let entry = LiveMusicEntry(id: "id1", creator: "T", title: nil, venue: "The Fillmore", coverage: nil, date: nil, year: nil, downloads: 1, dateString: "01-01", description: nil)
        XCTAssertEqual(entry.locationSummary, "The Fillmore")
    }

    func testDescriptionField() {
        let entry = LiveMusicEntry(id: "id1", creator: "T", title: nil, venue: nil, coverage: nil, date: nil, year: nil, downloads: 1, dateString: "01-01", description: "A great show at the Fillmore")
        XCTAssertEqual(entry.description, "A great show at the Fillmore")
    }

    // MARK: - Random

    func testRandomPickIsFromResults() async throws {
        // 5 entries, call fetchDailyEntry 20 times, verify each pick is one of the 5
        MockURLProtocol.requestHandler = { _ in
            let docs = (0..<5).map { i in
                #"{"identifier":"id\#(i)","creator":"Artist \#(i)","downloads":\#(100-i)}"#
            }.joined(separator: ",")
            let json = #"{"response":{"docs":[\#(docs)]}}"#
            return (HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let validIDs = Set((0..<5).map { "id\($0)" })
        // Clear cache each time to get a fresh random pick
        for _ in 0..<20 {
            service.clearCachedEntry()
            let entry = await service.fetchDailyEntry()
            XCTAssertNotNil(entry)
            XCTAssertTrue(validIDs.contains(entry!.id))
        }
    }

    func testDailyEntryReturnsNilOnEmpty() async {
        service.clearCachedEntry()
        MockURLProtocol.requestHandler = { _ in
            let json = #"{"response":{"docs":[]}}"#
            return (HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let entry = await service.fetchDailyEntry()
        XCTAssertNil(entry)
    }

    // MARK: - Date formatting

    func testTodayMMDDFormat() {
        let mmdd = LiveMusicOnThisDayService.todayMMDD()
        XCTAssertEqual(mmdd.count, 5)
        XCTAssertTrue(mmdd.contains("-"))
        let parts = mmdd.split(separator: "-")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue((1...12).contains(Int(parts[0]) ?? 0))
        XCTAssertTrue((1...31).contains(Int(parts[1]) ?? 0))
    }
}
