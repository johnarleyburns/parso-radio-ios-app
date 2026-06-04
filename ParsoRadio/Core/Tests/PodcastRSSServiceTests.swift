import XCTest
@testable import ParsoMusic

final class PodcastRSSServiceTests: XCTestCase {
    private var session: URLSession!
    private var mockProtocol: MockURLProtocol.Type!

    override func setUp() {
        super.setUp()
        mockProtocol = MockURLProtocol.self
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        super.tearDown()
    }

    func makeRSS(items: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>Test Podcast</title>
            \(items)
          </channel>
        </rss>
        """
    }

    func testParseSingleItem() async throws {
        let rss = makeRSS(items: """
            <item>
              <title>Episode 1</title>
              <enclosure url="https://example.com/audio.mp3" type="audio/mpeg" length="12345"/>
              <itunes:duration>30:00</itunes:duration>
            </item>
        """)

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com/feed.xml")!,
                                          statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, rss.data(using: .utf8)!)
        }

        let service = PodcastRSSService(session: session)
        let feedURL = URL(string: "https://example.com/feed.xml")!
        let channel = Channel(
            id: "test", name: "Test", category: "News", icon: "antenna.radiowaves.left.and.right",
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: feedURL.absoluteString
        )

        let tracks = try await service.fetchTracks(channel: channel)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].title, "Episode 1")
        XCTAssertEqual(tracks[0].duration, 1800)
    }

    func testParseMultipleItems() async throws {
        let rss = makeRSS(items: """
            <item>
              <title>Ep 1</title>
              <enclosure url="https://example.com/1.mp3" type="audio/mpeg"/>
              <itunes:duration>10:30</itunes:duration>
            </item>
            <item>
              <title>Ep 2</title>
              <enclosure url="https://example.com/2.mp3" type="audio/mpeg"/>
              <itunes:duration>15:45</itunes:duration>
            </item>
        """)

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com/feed.xml")!,
                                          statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, rss.data(using: .utf8)!)
        }

        let service = PodcastRSSService(session: session)
        let channel = Channel(
            id: "test", name: "Test", category: "News", icon: "antenna.radiowaves.left.and.right",
            contentType: .spokenWord,
            preferredSource: "podcast", feedURL: "https://example.com/feed.xml"
        )

        let tracks = try await service.fetchTracks(channel: channel)
        XCTAssertEqual(tracks.count, 2)
    }

    func testItemsWithoutEnclosuresAreSkipped() async throws {
        let rss = makeRSS(items: """
            <item>
              <title>No audio</title>
              <description>This item has no enclosure</description>
            </item>
            <item>
              <title>Has audio</title>
              <enclosure url="https://example.com/audio.mp3" type="audio/mpeg"/>
            </item>
        """)

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com/feed.xml")!,
                                          statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, rss.data(using: .utf8)!)
        }

        let service = PodcastRSSService(session: session)
        let channel = Channel(
            id: "test", name: "Test", category: "News", icon: "antenna.radiowaves.left.and.right",
            contentType: .spokenWord,
            preferredSource: "podcast", feedURL: "https://example.com/feed.xml"
        )

        let tracks = try await service.fetchTracks(channel: channel)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].title, "Has audio")
    }

    func testChannelWithoutFeedURLReturnsEmpty() async throws {
        let service = PodcastRSSService(session: session)
        let channel = Channel(
            id: "test", name: "Test", category: "News", icon: "antenna.radiowaves.left.and.right",
            contentType: .spokenWord,
            preferredSource: "podcast"
        )

        let tracks = try await service.fetchTracks(channel: channel)
        XCTAssertTrue(tracks.isEmpty)
    }

    func testHTTPErrorReturnsEmpty() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com/feed.xml")!,
                                          statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = PodcastRSSService(session: session)
        let channel = Channel(
            id: "test", name: "Test", category: "News", icon: "antenna.radiowaves.left.and.right",
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://example.com/feed.xml"
        )

        let tracks = try await service.fetchTracks(channel: channel)
        XCTAssertTrue(tracks.isEmpty)
    }

    func testDurationParsingMMSS() async throws {
        let rss = makeRSS(items: """
            <item>
              <title>Short</title>
              <enclosure url="https://example.com/audio.mp3" type="audio/mpeg"/>
              <itunes:duration>05:30</itunes:duration>
            </item>
        """)

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com/feed.xml")!,
                                          statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, rss.data(using: .utf8)!)
        }

        let service = PodcastRSSService(session: session)
        let channel = Channel(
            id: "test", name: "Test", category: "News", icon: "antenna.radiowaves.left.and.right",
            contentType: .spokenWord,
            preferredSource: "podcast", feedURL: "https://example.com/feed.xml"
        )

        let tracks = try await service.fetchTracks(channel: channel)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].duration, 330)
    }

    func testDurationParsingRawSeconds() async throws {
        let rss = makeRSS(items: """
            <item>
              <title>Raw seconds</title>
              <enclosure url="https://example.com/audio.mp3" type="audio/mpeg"/>
              <itunes:duration>120</itunes:duration>
            </item>
        """)

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com/feed.xml")!,
                                          statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, rss.data(using: .utf8)!)
        }

        let service = PodcastRSSService(session: session)
        let channel = Channel(
            id: "test", name: "Test", category: "News", icon: "antenna.radiowaves.left.and.right",
            contentType: .spokenWord,
            preferredSource: "podcast", feedURL: "https://example.com/feed.xml"
        )

        let tracks = try await service.fetchTracks(channel: channel)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].duration, 120)
    }

    func testNetworkErrorThrows() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = PodcastRSSService(session: session)
        let channel = Channel(
            id: "test", name: "Test", category: "News", icon: "antenna.radiowaves.left.and.right",
            contentType: .spokenWord,
            preferredSource: "podcast", feedURL: "https://example.com/feed.xml"
        )

        do {
            _ = try await service.fetchTracks(channel: channel)
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }
    }
}
