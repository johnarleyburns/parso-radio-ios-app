import XCTest
@testable import ParsoMusic

final class LiveMusicOnThisDayIntegrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 120
    }

    func testEtreeQueryReturnsResults() async throws {
        let service = LiveMusicOnThisDayService()
        let entries: [LiveMusicEntry]
        do {
            entries = try await service.fetchEntries(for: "05-08")
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Etree 05-08: \(entries.count) entries")
        for e in entries.prefix(3) {
            print("  [\(e.id)] \(e.creator) — \(e.date ?? "nil")")
        }
        XCTAssertFalse(entries.isEmpty, "Expected ≥1 live music entry for 05-08")
        XCTAssertTrue(entries.contains { $0.creator == "Grateful Dead" },
                       "Expected Grateful Dead entries for 05-08")
    }

    func testThumbnailLoads() async throws {
        let knownID = "gd1977-05-08"
        let url = URL(string: "https://archive.org/services/img/\(knownID)")!
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Expected HTTP response")
            return
        }
        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertGreaterThan(data.count, 2048, "Thumbnail should be larger than 2KB (not IA placeholder)")
    }

    func testJuly4QueryReturnsResults() async throws {
        let service = LiveMusicOnThisDayService()
        let entries: [LiveMusicEntry]
        do {
            entries = try await service.fetchEntries(for: "07-04")
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Etree 07-04: \(entries.count) entries")
        for e in entries.prefix(3) {
            print("  [\(e.id)] \(e.creator) — \(e.date ?? "nil")")
        }
        XCTAssertFalse(entries.isEmpty, "Expected ≥1 live music entry for 07-04")
    }

    func testMetadataEnrichment() async throws {
        let knownID = "gd1977-05-08"
        guard let encoded = knownID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://archive.org/metadata/\(encoded)") else {
            XCTFail("Invalid URL")
            return
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            XCTFail("Expected HTTP 200 for metadata")
            return
        }
        struct Envelope: Decodable {
            struct Meta: Decodable {
                let title: String?
                let creator: String?
                let date: String?
            }
            let metadata: Meta
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        XCTAssertNotNil(envelope.metadata.title, "Expected non-nil title in metadata")
        XCTAssertNotNil(envelope.metadata.creator, "Expected non-nil creator in metadata")
        print("Metadata: title=\(envelope.metadata.title ?? "nil"), creator=\(envelope.metadata.creator ?? "nil")")
    }

    func testFetchTracksForKnownItem() async throws {
        let service = InternetArchiveService()
        let knownID = "gd1977-05-08"
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracksForIdentifier(knownID)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Tracks for \(knownID): \(tracks.count)")
        for t in tracks.prefix(5) {
            print("  \(t.title) — \(t.duration.formattedTime)")
        }
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 playable track for \(knownID)")
    }
}
