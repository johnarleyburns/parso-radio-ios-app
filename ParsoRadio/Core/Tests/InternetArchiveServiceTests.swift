import XCTest
@testable import ParsoMusic

final class InternetArchiveServiceTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchTracksReturnsValidTracks() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"response":{"docs":[
              {"identifier":"bach-001","title":"Brandenburg Concerto No. 3",
               "creator":"Johann Sebastian Bach",
               "subject":["strings","violin","baroque"],
               "licenseurl":"https://creativecommons.org/publicdomain/mark/1.0/",
               "year":1920,"collection":["audio"]}
            ]}}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = InternetArchiveService(session: session)
        let tracks = try await service.fetchTracks(composers: ["bach"], instruments: ["strings"])
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].id, "bach-001")
        XCTAssertEqual(tracks[0].composer, "bach")
        XCTAssertTrue(tracks[0].instruments.contains("strings"))
        XCTAssertEqual(tracks[0].license, .publicDomain)
    }

    func testMusopenTracksAreCC0() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"response":{"docs":[
              {"identifier":"musopen-chopin-001","title":"Nocturne Op. 9 No. 2",
               "creator":"Chopin","subject":["piano"],
               "collection":["musopen","audio"]}
            ]}}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = InternetArchiveService(session: session)
        let tracks = try await service.fetchMusopenTracks(composer: "chopin")
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].license, .cc0)
        XCTAssertEqual(tracks[0].composer, "chopin")
    }

    func testRejectedLicenseFiltered() async throws {
        // Track has no licenseurl and year 1980 (not public domain) — must be filtered out.
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"response":{"docs":[
              {"identifier":"no-license-001","title":"Some Track",
               "creator":"Johann Sebastian Bach",
               "subject":["strings"],
               "year":1980,"collection":["audio"]}
            ]}}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = InternetArchiveService(session: session)
        let tracks = try await service.fetchTracks(composers: ["bach"], instruments: ["strings"])
        XCTAssertTrue(tracks.isEmpty)
    }

    func testSubjectStringDecodedAsArray() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"response":{"docs":[
              {"identifier":"single-subject","title":"Violin Concerto",
               "creator":"Antonio Vivaldi",
               "subject":"violin",
               "licenseurl":"https://creativecommons.org/publicdomain/mark/1.0/",
               "year":1910,"collection":["audio"]}
            ]}}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = InternetArchiveService(session: session)
        let tracks = try await service.fetchTracks(composers: ["vivaldi"], instruments: ["strings"])
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].composer, "vivaldi")
    }

    func testResolveAudioURLFindsFirstMP3() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"files":[
              {"name":"cover.jpg","format":"JPEG"},
              {"name":"track.mp3","format":"VBR MP3"},
              {"name":"track_64.mp3","format":"64Kbps MP3"}
            ]}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = InternetArchiveService(session: session)
        let url = try await service.resolveAudioURL(for: "test-item")
        XCTAssertEqual(url.absoluteString, "https://archive.org/download/test-item/track.mp3")
    }

    func testResolveAudioURLThrowsWhenNoAudioFile() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"files":[{"name":"cover.jpg","format":"JPEG"}]}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = InternetArchiveService(session: session)
        do {
            _ = try await service.resolveAudioURL(for: "test-item")
            XCTFail("Expected throw")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testNetworkErrorThrows() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let service = InternetArchiveService(session: session)
        do {
            _ = try await service.fetchTracks(tags: ["classical"])
            XCTFail("Expected throw")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testAddedDateParsedFromISOString() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"response":{"docs":[
              {"identifier":"dated-001","title":"Goldberg Variations",
               "creator":"Johann Sebastian Bach",
               "subject":["piano","baroque"],
               "licenseurl":"https://creativecommons.org/publicdomain/mark/1.0/",
               "year":1925,"collection":["audio"],
               "addeddate":"2023-08-15T14:30:00.000000"}
            ]}}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = InternetArchiveService(session: session)
        let tracks = try await service.fetchTracks(composers: ["bach"], instruments: ["piano"])
        XCTAssertEqual(tracks.count, 1)
        XCTAssertNotNil(tracks[0].addedDate, "addeddate field must be parsed into Track.addedDate")
        if let date = tracks[0].addedDate {
            let cal = Calendar(identifier: .gregorian)
            let comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
            XCTAssertEqual(comps.year, 2023)
            XCTAssertEqual(comps.month, 8)
            XCTAssertEqual(comps.day, 15)
        }
    }

    func testMissingAddedDateResultsInNil() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"response":{"docs":[
              {"identifier":"nodated-001","title":"Cello Suite",
               "creator":"Johann Sebastian Bach",
               "subject":["cello"],
               "licenseurl":"https://creativecommons.org/publicdomain/mark/1.0/",
               "year":1920,"collection":["audio"]}
            ]}}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = InternetArchiveService(session: session)
        let tracks = try await service.fetchTracks(composers: ["bach"], instruments: ["cello"])
        XCTAssertEqual(tracks.count, 1)
        XCTAssertNil(tracks[0].addedDate, "Track without addeddate must have addedDate == nil")
    }

    // MARK: - Search

    func testSearchReturnsResultGroups() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"response":{"docs":[
              {"identifier":"beethoven-sym3","title":"Symphony No. 3",
               "creator":"Ludwig van Beethoven","addeddate":"2023-01-10T12:00:00.000000"},
              {"identifier":"beethoven-sym5","title":"Symphony No. 5",
               "creator":"Ludwig van Beethoven","addeddate":"2022-06-01T08:00:00.000000"}
            ]}}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        let service = InternetArchiveService(session: session)
        let groups = try await service.search(query: "beethoven", page: 0)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].id, "beethoven-sym3")
        XCTAssertEqual(groups[0].title, "Symphony No. 3")
        XCTAssertEqual(groups[0].creator, "Ludwig van Beethoven")
        XCTAssertEqual(groups[0].source, .internetArchive)
        XCTAssertNotNil(groups[0].addedDate)
    }

    func testSearchLibrivoxHasLibrivoxSource() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"response":{"docs":[
              {"identifier":"sherlock-holmes-librivox","title":"Adventures of Sherlock Holmes",
               "creator":"Arthur Conan Doyle","addeddate":"2021-03-15T00:00:00.000000"}
            ]}}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        let service = InternetArchiveService(session: session)
        let groups = try await service.searchLibrivox(query: "sherlock", page: 0)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].source, .librivox)
        XCTAssertEqual(groups[0].id, "sherlock-holmes-librivox")
    }

    func testSearchPaginationSetsStartParam() async throws {
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = """{"response":{"docs":[]}}"""
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        let service = InternetArchiveService(session: session)
        _ = try await service.search(query: "bach", page: 2)
        let urlString = capturedURL?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("start=40"), "page 2 should use start=40, got: \(urlString)")
    }

    func testFetchTracksForIdentifierReturnsAudioFiles() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "files":[
                {"name":"track01.mp3","format":"VBR MP3","length":"240.5",
                 "title":"Aria da Capo","creator":"J.S. Bach"},
                {"name":"track02.mp3","format":"128Kbps MP3","length":"180.0",
                 "title":"Allemande","creator":"J.S. Bach"},
                {"name":"cover.jpg","format":"JPEG"}
              ],
              "metadata":{"title":"Goldberg Variations","creator":"J.S. Bach",
                          "licenseurl":"https://creativecommons.org/publicdomain/mark/1.0/"}
            }
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        let service = InternetArchiveService(session: session)
        let tracks = try await service.fetchTracksForIdentifier("goldberg-vars-001")
        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks[0].title, "Aria da Capo")
        XCTAssertEqual(tracks[0].duration, 240.5)
        XCTAssertEqual(tracks[0].partNumber, 1)
        XCTAssertEqual(tracks[0].totalParts, 2)
        XCTAssertEqual(tracks[0].parentIdentifier, "goldberg-vars-001")
        XCTAssertTrue(tracks[0].streamURL.absoluteString.contains("archive.org/download/goldberg-vars-001/track01.mp3"))
        XCTAssertEqual(tracks[0].license, .publicDomain)
    }

    func testFetchTracksForIdentifierSingleFileHasNoPartInfo() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "files":[
                {"name":"symphony.mp3","format":"VBR MP3","length":"1800.0",
                 "title":"Symphony No. 5","creator":"Beethoven"}
              ],
              "metadata":{"title":"Symphony No. 5","creator":"Beethoven",
                          "licenseurl":"https://creativecommons.org/publicdomain/mark/1.0/"}
            }
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        let service = InternetArchiveService(session: session)
        let tracks = try await service.fetchTracksForIdentifier("beethoven-sym5")
        XCTAssertEqual(tracks.count, 1)
        XCTAssertNil(tracks[0].partNumber)
        XCTAssertNil(tracks[0].totalParts)
        XCTAssertNil(tracks[0].parentIdentifier)
    }
}

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
