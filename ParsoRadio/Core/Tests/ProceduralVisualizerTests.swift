import XCTest
@testable import ParsoMusic

final class ProceduralVisualizerTests: XCTestCase {

    // Seed → hue must be deterministic across launches (stable djb2, NOT
    // String.hashValue) so a track always renders the same distinct look.
    func testHueIsDeterministicAndInRange() {
        for seed in ["track-1", "internet_archive/laws_plato.mp3", "", "🎵x"] {
            let a = ProceduralVisualizerView.hue(for: seed)
            let b = ProceduralVisualizerView.hue(for: seed)
            XCTAssertEqual(a, b, "same seed must yield the same hue")
            XCTAssertGreaterThanOrEqual(a, 0.0)
            XCTAssertLessThan(a, 1.0, "hue must be normalised to [0,1)")
        }
    }

    func testDifferentTracksGetDifferentLooks() {
        let h1 = ProceduralVisualizerView.hue(for: "song-A")
        let h2 = ProceduralVisualizerView.hue(for: "song-B")
        XCTAssertNotEqual(h1, h2,
            "distinct tracks should get distinct palettes (no stale repeats)")
    }
}
