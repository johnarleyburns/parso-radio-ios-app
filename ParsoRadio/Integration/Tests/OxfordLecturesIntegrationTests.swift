import XCTest
@testable import ParsoRadio

// Integration tests for OxfordLecturesService.
// These tests hit the live podcasts.ox.ac.uk website.
// URLErrors are skipped so CI isn't blocked by transient network issues.
final class OxfordLecturesIntegrationTests: XCTestCase {

    private let service = OxfordLecturesService()

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 90
    }

    func testPhilosophyChannelReturnsAtLeastOneTrack() async throws {
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(unitSlug: "faculty-philosophy")
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Oxford Philosophy: \(tracks.count) tracks")
        for t in tracks.prefix(3) { print("  \(t.title) | \(t.duration)s | \(t.streamURL)") }
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 track from Oxford Philosophy unit")
        XCTAssertTrue(tracks.allSatisfy { $0.source == "oxford_lectures" },
            "All tracks must have source 'oxford_lectures'")
        XCTAssertTrue(tracks.allSatisfy { $0.license == .ccBy },
            "All Oxford tracks must carry CC BY license")
    }

    func testPhilosophyTracksMatchPhilosophyChannel() async throws {
        let channel = Channel.defaults.first { $0.id == "oxford-philosophy" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(unitSlug: channel.tags.first ?? "")
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard let first = tracks.first else {
            throw XCTSkip("No tracks returned — cannot verify tag matching")
        }
        XCTAssertTrue(channel.matches(first),
            "Fetched track must pass Channel.matches() — tags: \(first.tags)")
    }

    func testPhysicsChannelReturnsAtLeastOneTrack() async throws {
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(unitSlug: "department-physics")
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Oxford Physics: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 track from Oxford Physics unit")
    }
}
