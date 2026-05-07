import XCTest
@testable import ParsoRadio

// These tests hit the real Internet Archive API.
// URLErrors (network down, timeout) are skipped so CI isn't blocked by IA outages.
// Filtering failures (0 tracks returned despite a successful HTTP call) are hard
// failures — that's the bug class we want to catch.
final class InternetArchiveIntegrationTests: XCTestCase {

    private let service = InternetArchiveService()

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 60
    }

    func testBachVivaldiStringsChannelReturnsAtLeastOnTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(
                composers: channel.composers,
                instruments: channel.instruments
            )
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Bach/Vivaldi strings: \(tracks.count) tracks passed filtering")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title) — instruments: \(t.instruments)")
        }
        XCTAssertFalse(
            tracks.isEmpty,
            "Expected ≥1 Bach/Vivaldi strings track but got 0. " +
            "Check composerQuery and InstrumentDetector coverage."
        )
        XCTAssertTrue(
            tracks.allSatisfy { $0.license != .rejected },
            "All tracks should have a valid license"
        )
    }

    func testChopinRachmaninoffPianoChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "chopin-rachmaninoff-piano" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(
                composers: channel.composers,
                instruments: channel.instruments
            )
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Chopin/Rachmaninoff piano: \(tracks.count) tracks passed filtering")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title) — instruments: \(t.instruments)")
        }
        XCTAssertFalse(
            tracks.isEmpty,
            "Expected ≥1 Chopin/Rachmaninoff piano track but got 0. " +
            "Check composerQuery and InstrumentDetector coverage."
        )
    }

    func testClassicalTagChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "classical" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(tags: channel.tags)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Classical tag: \(tracks.count) tracks passed filtering")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title)")
        }
        XCTAssertFalse(
            tracks.isEmpty,
            "Expected ≥1 classical tag track but got 0. " +
            "Check confidenceThreshold for tag-based channels."
        )
    }

    func testAmbientTagChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "ambient" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(tags: channel.tags)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Ambient tag: \(tracks.count) tracks passed filtering")
        XCTAssertFalse(
            tracks.isEmpty,
            "Expected ≥1 ambient tag track but got 0."
        )
    }

    func testResolveAudioURLReturnsPlayableFileURL() async throws {
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(
                composers: ["bach"],
                instruments: ["strings"]
            )
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard let first = tracks.first else {
            throw XCTSkip("No tracks returned by search — cannot test URL resolution")
        }
        let url: URL
        do {
            url = try await service.resolveAudioURL(for: first.id)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable during URL resolution: \(e.localizedDescription)")
        }
        print("Resolved audio URL: \(url.absoluteString)")
        XCTAssertTrue(
            url.absoluteString.contains("archive.org/download/"),
            "URL should be an IA download URL"
        )
        let ext = url.pathExtension.lowercased()
        XCTAssertTrue(
            ["mp3", "ogg", "flac", "m4a"].contains(ext),
            "Expected an audio file extension, got: \(ext)"
        )
    }
}
