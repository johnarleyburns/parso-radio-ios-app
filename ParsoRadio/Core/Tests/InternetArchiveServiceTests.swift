import XCTest
@testable import ParsoRadio

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
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"response":{"docs":[
              {"identifier":"cc-nc-001","title":"Some Track",
               "creator":"Johann Sebastian Bach",
               "subject":["strings"],
               "licenseurl":"https://creativecommons.org/licenses/by-nc/4.0/",
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
