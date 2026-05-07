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

    // Tests Chopin because IA's musopen collection has only 34 items and Bach/Vivaldi/Rachmaninoff
    // are not among them. Chopin is present as musopen-chopin with 208 audio files.
    func testMusopenChopinReturnsAtLeastOneTrack() async throws {
        let tracks: [Track]
        do {
            tracks = try await service.fetchMusopenTracks(composer: "chopin")
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Musopen Chopin: \(tracks.count) tracks")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title)")
        }
        XCTAssertFalse(
            tracks.isEmpty,
            "Expected ≥1 Musopen Chopin track but got 0. " +
            "Check fetchMusopenTracks title/subject query and IA musopen collection."
        )
        XCTAssertTrue(
            tracks.allSatisfy { $0.license != .rejected },
            "All Musopen tracks should have a valid license"
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

// MARK: - Spoken-word (LibriVox) integration tests

final class SpokenWordIntegrationTests: XCTestCase {

    private let service = InternetArchiveService()

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 60
    }

    func testGreekPhilosophyChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "greek-philosophy" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchSpokenWordTracks(channel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Greek Philosophy: \(tracks.count) tracks")
        for t in tracks.prefix(3) { print("  \(t.title) | \(t.license)") }
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 LibriVox philosophy track but got 0.")
        XCTAssertTrue(tracks.allSatisfy { $0.license != .rejected }, "All tracks must have valid license")
    }

    func testChildrensBooksChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "childrens-books" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchSpokenWordTracks(channel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Children's Books: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 LibriVox children's track but got 0.")
    }

    func testScienceFictionChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "science-fiction" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchSpokenWordTracks(channel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Science Fiction: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 LibriVox sci-fi track but got 0.")
    }

    func testSpokenWordTracksHaveChannelTagsForMatching() async throws {
        let channel = Channel.defaults.first { $0.id == "greek-philosophy" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchSpokenWordTracks(channel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard let first = tracks.first else {
            throw XCTSkip("No tracks returned — cannot verify tag matching")
        }
        XCTAssertTrue(
            channel.matches(first),
            "Fetched track must pass Channel.matches() — tags: \(first.tags)"
        )
    }
}

// MARK: - FMA scraper integration tests

final class FMAIntegrationTests: XCTestCase {

    private let service = FMAService()

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 60
    }

    func testClassicalChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "classical" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Classical: \(tracks.count) tracks")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title) | \(t.streamURL.absoluteString)")
        }
        XCTAssertFalse(
            tracks.isEmpty,
            "Expected ≥1 FMA Classical public-domain track but got 0."
        )
        XCTAssertTrue(
            tracks.allSatisfy { $0.source == "fma" },
            "All tracks should have source 'fma'"
        )
    }

    func testAmbientChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "ambient" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Ambient: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA Ambient track but got 0.")
    }

    func testJazzBarChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "jazz-bar" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Jazz Bar: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA Jazz track but got 0.")
    }

    func testRockChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "rock" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Rock: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA Rock track but got 0.")
    }

    func testSoulRnbChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "soul-rnb" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Soul & R&B: \(tracks.count) tracks")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title) | \(t.license)")
        }
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA Soul-RB public-domain track but got 0.")
    }

    func testOldTimeRootsChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "old-time-roots" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Old-Time & Roots: \(tracks.count) tracks")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title) | \(t.license)")
        }
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA Old-Time public-domain track but got 0.")
    }

    func testStreamURLRedirectsToMp3() async throws {
        let channel = Channel.defaults.first { $0.id == "classical" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard let first = tracks.first else {
            throw XCTSkip("No FMA tracks returned — cannot test stream URL")
        }
        // Follow the redirect to verify it lands on a real MP3.
        var request = URLRequest(url: first.streamURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable following stream URL: \(e.localizedDescription)")
        }
        let finalURL = (response as? HTTPURLResponse)?.url ?? response.url!
        print("FMA stream resolved to: \(finalURL.absoluteString)")
        XCTAssertTrue(
            finalURL.absoluteString.contains("freemusicarchive.org") ||
            finalURL.absoluteString.contains("files.freemusicarchive.org"),
            "Expected stream URL to resolve within FMA CDN, got: \(finalURL)"
        )
    }
}
