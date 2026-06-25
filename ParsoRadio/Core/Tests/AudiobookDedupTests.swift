import XCTest
@testable import ParsoMusic

/// Issue #2: an IA item that ships each chapter at multiple MP3 bitrates
/// (64k/128k/VBR) previously surfaced every chapter 3× in the chapter list.
/// `fetchTracksForIdentifier` must collapse the variants to one chapter each,
/// and `dedupeParts` / `partsAreClean` must repair stale tripled DB rows.
@MainActor
final class AudiobookDedupTests: XCTestCase {
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

    // FAILS before the fix (returns 15 tracks); PASSES after (5 unique chapters).
    func testFetchTracksDedupesMultipleMP3Bitrates() async throws {
        MockURLProtocol.requestHandler = { _ in
            var files = ""
            for n in 1...5 {
                let nn = String(format: "%02d", n)
                files += """
                {"name":"ch_\(nn)_64.mp3","format":"64Kbps MP3","length":"5:00","title":"Chapter \(n)"},
                {"name":"ch_\(nn)_128.mp3","format":"128Kbps MP3","length":"5:00","title":"Chapter \(n)"},
                {"name":"ch_\(nn)_vbr.mp3","format":"VBR MP3","length":"5:00","title":"Chapter \(n)"},
                {"name":"ch_\(nn).ogg","format":"Ogg Vorbis","length":"300","title":"Chapter \(n)"},
                """
            }
            files = String(files.dropLast())
            let json = """
            { "files":[\(files)],
              "metadata":{"title":"Gallipoli","creator":"John Masefield",
                          "licenseurl":"https://creativecommons.org/publicdomain/mark/1.0/"} }
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!,
                                           statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let service = InternetArchiveService(session: session)
        let tracks = try await service.fetchTracksForIdentifier("gallipoli_ia")

        XCTAssertEqual(tracks.count, 5, "5 chapters, not 15 bitrate variants")
        XCTAssertEqual(tracks.map(\.title), (1...5).map { "Chapter \($0)" })
        XCTAssertEqual(tracks.map(\.partNumber), [1, 2, 3, 4, 5])
        XCTAssertTrue(tracks.allSatisfy { $0.streamURL.absoluteString.hasSuffix(".mp3") })
        // Highest-bitrate variant (VBR) wins over 64k/128k.
        XCTAssertTrue(tracks.allSatisfy { $0.streamURL.absoluteString.contains("_vbr.mp3") })
        XCTAssertTrue(tracks.allSatisfy { $0.parentIdentifier == "gallipoli_ia" })
    }

    func testItemInfoCollapsesDuplicateBitrates() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            { "files":[
              {"name":"ch_01_64.mp3","format":"64Kbps MP3","length":"60"},
              {"name":"ch_01_128.mp3","format":"128Kbps MP3","length":"60"},
              {"name":"ch_02_64.mp3","format":"64Kbps MP3","length":"120"},
              {"name":"ch_02_128.mp3","format":"128Kbps MP3","length":"120"}
            ] }
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://archive.org")!,
                                           statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        let service = InternetArchiveService(session: session)
        let info = await service.itemInfo(forIdentifier: "x")
        XCTAssertEqual(info?.audioCount, 2, "2 unique chapters, not 4 variants")
        XCTAssertEqual(info?.duration ?? 0, 180, accuracy: 0.01, "duration not triple-counted")
    }

    // dedupeParts collapses tripled DB rows and renumbers sequentially.
    func testDedupePartsCollapsesAndRenumbers() {
        var parts: [Track] = []
        var pn = 0
        for n in 1...3 {
            for bitrate in ["64kb", "128kb", "vbr"] {
                pn += 1
                parts.append(Track.makeStub(
                    id: "bk/ch_\(n)_\(bitrate).mp3",
                    title: "Chapter \(n)",
                    parentIdentifier: "bk").withPart(pn))
            }
        }
        let deduped = PlayerViewModel.dedupeParts(parts)
        XCTAssertEqual(deduped.count, 3)
        XCTAssertEqual(deduped.map(\.partNumber), [1, 2, 3])
        XCTAssertEqual(Set(deduped.map(\.title)).count, 3)
    }

    func testPartsAreCleanRejectsDuplicateChapters() {
        var parts: [Track] = []
        var pn = 0
        for bitrate in ["64kb", "128kb", "vbr"] {
            pn += 1
            parts.append(Track.makeStub(
                id: "bk/ch_01_\(bitrate).mp3", title: "Chapter 1",
                parentIdentifier: "bk").withPart(pn))
        }
        XCTAssertFalse(PlayerViewModel.partsAreClean(parts),
                       "three variants of the same chapter is not a clean part set")
    }
}

private extension Track {
    func withPart(_ n: Int) -> Track {
        var c = self
        c.partNumber = n
        c.totalParts = nil
        return c
    }
}
