import XCTest
@testable import ParsoMusic

final class PlayerSurfaceSpecTests: XCTestCase {

    func testMusicSurfaceSpecIncludesScrubElapsedAndRemaining() {
        let spec = PlayerSurfaceSpec.spec(for: .music)
        XCTAssertTrue(spec.includesScrubSlider, "Music surface must include scrub slider")
        XCTAssertTrue(spec.includesElapsedTime, "Music surface must include elapsed time")
        XCTAssertTrue(spec.includesRemainingTime, "Music surface must include remaining time")
        XCTAssertFalse(spec.includesWorkTimeLeft, "Music surface must not include work time left")
        XCTAssertFalse(spec.includesJogControls, "Music surface must not include jog controls")
    }

    func testAudiobookSurfaceSpecIncludesFullSpokenControls() {
        let spec = PlayerSurfaceSpec.spec(for: .audiobook)
        XCTAssertTrue(spec.includesScrubSlider, "Audiobook surface must include scrub slider")
        XCTAssertTrue(spec.includesElapsedTime, "Audiobook surface must include elapsed time")
        XCTAssertTrue(spec.includesRemainingTime, "Audiobook surface must include remaining time")
        XCTAssertTrue(spec.includesWorkTimeLeft, "Audiobook surface must include work time left")
        XCTAssertTrue(spec.includesJogControls, "Audiobook surface must include jog controls")
        XCTAssertTrue(spec.includesSpeedControl, "Audiobook surface must include speed control")
        XCTAssertTrue(spec.includesChapters, "Audiobook surface must include chapters")
        XCTAssertTrue(spec.includesBookmarks, "Audiobook surface must include bookmarks")
        XCTAssertTrue(spec.includesSleepTimer, "Audiobook surface must include sleep timer")
    }

    func testLectureSurfaceSpecMatchesAudiobook() {
        let spec = PlayerSurfaceSpec.spec(for: .lecture)
        XCTAssertTrue(spec.includesScrubSlider)
        XCTAssertTrue(spec.includesElapsedTime)
        XCTAssertTrue(spec.includesRemainingTime)
        XCTAssertTrue(spec.includesWorkTimeLeft)
        XCTAssertTrue(spec.includesJogControls)
        XCTAssertTrue(spec.includesSpeedControl)
        XCTAssertTrue(spec.includesBookmarks)
    }

    func testPodcastSurfaceSpecIncludesScrubAndJogButNotWorkLeft() {
        let spec = PlayerSurfaceSpec.spec(for: .podcast)
        XCTAssertTrue(spec.includesScrubSlider)
        XCTAssertTrue(spec.includesElapsedTime)
        XCTAssertTrue(spec.includesRemainingTime)
        XCTAssertTrue(spec.includesJogControls)
        XCTAssertTrue(spec.includesSpeedControl)
        XCTAssertTrue(spec.includesBookmarks)
        XCTAssertFalse(spec.includesWorkTimeLeft, "Podcast surface does not show work time left")
    }

    func testAmbientSurfaceSpecExcludesAllFiniteProgressControls() {
        let spec = PlayerSurfaceSpec.spec(for: .ambient)
        XCTAssertFalse(spec.includesScrubSlider, "Ambient must not include scrub slider")
        XCTAssertFalse(spec.includesElapsedTime, "Ambient must not include elapsed time")
        XCTAssertFalse(spec.includesRemainingTime, "Ambient must not include remaining time")
        XCTAssertFalse(spec.includesWorkTimeLeft, "Ambient must not include work time left")
        XCTAssertFalse(spec.includesJogControls, "Ambient must not include jog controls")
    }

    func testAllFiniteNonAmbientSpecsIncludeScrubElapsedRemaining() {
        let finiteKinds: [MediaKind] = [.music, .audiobook, .lecture, .podcast]
        for kind in finiteKinds {
            let spec = PlayerSurfaceSpec.spec(for: kind)
            XCTAssertTrue(spec.includesScrubSlider, "\(kind) must include scrub slider")
            XCTAssertTrue(spec.includesElapsedTime, "\(kind) must include elapsed time")
            XCTAssertTrue(spec.includesRemainingTime, "\(kind) must include remaining time")
        }
    }

    func testAllSpecsRejectNonMP3Playback() {
        for kind in MediaKind.allCases {
            let spec = PlayerSurfaceSpec.spec(for: kind)
            XCTAssertTrue(spec.requiresMP3Only, "\(kind) surface spec must require MP3-only policy")
        }
    }
}
