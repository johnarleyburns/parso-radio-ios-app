import XCTest
@testable import ParsoMusic

/// Full matrix for the pure `PlaybackTransitionPolicy`. No AVPlayer, network, or
/// view models — just (outgoing kind, incoming kind, reason) → style.
final class PlaybackTransitionPolicyTests: XCTestCase {

    private let policy = PlaybackTransitionPolicy()

    // MARK: Music

    func testMusicManualNextFadesOutIn() {
        XCTAssertEqual(policy.style(from: .music, to: .music, reason: .manualNext),
                       .fadeOutIn(out: 0.25, in: 0.25))
    }

    func testMusicManualPreviousFadesOutIn() {
        XCTAssertEqual(policy.style(from: .music, to: .music, reason: .manualPrevious),
                       .fadeOutIn(out: 0.25, in: 0.25))
    }

    func testMusicNaturalAdvanceFadesInOnly_Phase1() {
        // Phase 1 ships fade-in only; no true overlap crossfade.
        XCTAssertEqual(policy.style(from: .music, to: .music, reason: .naturalAdvance),
                       .fadeIn(duration: 0.2))
    }

    func testMusicContextSwitchesFadeOutIn() {
        for reason: PlaybackTransitionReason in [.channelChange, .playlistChange,
                                                 .directItemChange, .searchAudition] {
            XCTAssertEqual(policy.style(from: .music, to: .music, reason: reason),
                           .fadeOutIn(out: 0.30, in: 0.25),
                           "music \(reason) should fade out/in")
        }
    }

    func testMusicNeverGetsCrossfadeInPhase1() {
        for reason: PlaybackTransitionReason in [.naturalAdvance, .manualNext, .manualPrevious,
                                                 .channelChange, .playlistChange,
                                                 .directItemChange, .searchAudition] {
            if case .musicCrossfade = policy.style(from: .music, to: .music, reason: reason) {
                XCTFail("Phase 1 must not emit musicCrossfade for \(reason)")
            }
        }
    }

    // MARK: Spoken (audiobook / lecture / podcast)

    func testAudiobookSameWorkNaturalAdvanceIsImmediate() {
        XCTAssertEqual(policy.style(from: .audiobook, to: .audiobook,
                                    reason: .naturalAdvance, sameWork: true),
                       .immediate)
    }

    func testLectureNewWorkNaturalAdvanceIsImmediate() {
        XCTAssertEqual(policy.style(from: .lecture, to: .lecture, reason: .naturalAdvance),
                       .immediate)
    }

    func testPodcastNaturalNextEpisodeIsImmediate() {
        XCTAssertEqual(policy.style(from: .podcast, to: .podcast, reason: .naturalAdvance),
                       .immediate)
    }

    func testSpokenManualNavigationFadesOutInShort() {
        XCTAssertEqual(policy.style(from: .audiobook, to: .audiobook, reason: .manualNext),
                       .fadeOutIn(out: 0.2, in: 0.2))
        XCTAssertEqual(policy.style(from: .podcast, to: .podcast, reason: .directItemChange),
                       .fadeOutIn(out: 0.2, in: 0.2))
        XCTAssertEqual(policy.style(from: .lecture, to: .lecture, reason: .manualPrevious),
                       .fadeOutIn(out: 0.2, in: 0.2))
    }

    // MARK: Mixed media

    func testMixedMusicToSpokenNeverCrossfades() {
        for (out, inc): (MediaKind, MediaKind) in [(.music, .audiobook), (.audiobook, .music),
                                                   (.music, .podcast), (.lecture, .music)] {
            let style = policy.style(from: out, to: inc, reason: .playlistChange)
            if case .musicCrossfade = style { XCTFail("mixed \(out)->\(inc) must not crossfade") }
            XCTAssertEqual(style, .fadeOutIn(out: 0.30, in: 0.25))
        }
    }

    func testMixedNaturalAdvanceIsImmediate() {
        XCTAssertEqual(policy.style(from: .music, to: .audiobook, reason: .naturalAdvance),
                       .immediate)
        XCTAssertEqual(policy.style(from: .audiobook, to: .music, reason: .naturalAdvance),
                       .immediate)
    }

    // MARK: Ambient

    func testAmbientIncomingFadesIn() {
        XCTAssertEqual(policy.style(from: .music, to: .ambient, reason: .channelChange),
                       .fadeIn(duration: 0.8))
        XCTAssertEqual(policy.style(from: nil, to: .ambient, reason: .channelChange),
                       .fadeIn(duration: 0.8))
    }

    func testAmbientOutgoingFadesOutInNoCrossfade() {
        let style = policy.style(from: .ambient, to: .music, reason: .channelChange)
        if case .musicCrossfade = style { XCTFail("ambient must never crossfade") }
        XCTAssertEqual(style, .fadeOutIn(out: 0.5, in: 0.25))
    }

    func testLoopingForcesFadeIn() {
        XCTAssertEqual(policy.style(from: .ambient, to: .ambient,
                                    reason: .channelChange, looping: true),
                       .fadeIn(duration: 0.8))
    }

    // MARK: Recovery / teardown / sleep

    func testRecoveryPathsAreImmediate() {
        for reason: PlaybackTransitionReason in [.retryAfterFailure, .nonAudioSkip,
                                                 .stallSkip, .stop, .resume] {
            XCTAssertEqual(policy.style(from: .music, to: .music, reason: reason), .immediate,
                           "\(reason) must be immediate")
            XCTAssertEqual(policy.style(from: .audiobook, to: .audiobook, reason: reason), .immediate)
        }
    }

    func testSleepTimerFadesOut() {
        XCTAssertEqual(policy.style(from: .music, to: .music, reason: .sleepTimer),
                       .fadeOut(duration: 10))
    }

    func testNilIncomingIsImmediate() {
        XCTAssertEqual(policy.style(from: .music, to: nil, reason: .manualNext), .immediate)
    }

    // MARK: Style component accessors

    func testStyleComponentDurations() {
        XCTAssertNil(AudioTransitionStyle.immediate.outDuration)
        XCTAssertNil(AudioTransitionStyle.immediate.inDuration)

        XCTAssertNil(AudioTransitionStyle.fadeIn(duration: 0.2).outDuration)
        XCTAssertEqual(AudioTransitionStyle.fadeIn(duration: 0.2).inDuration, 0.2)

        XCTAssertEqual(AudioTransitionStyle.fadeOut(duration: 10).outDuration, 10)
        XCTAssertNil(AudioTransitionStyle.fadeOut(duration: 10).inDuration)

        XCTAssertEqual(AudioTransitionStyle.fadeOutIn(out: 0.3, in: 0.25).outDuration, 0.3)
        XCTAssertEqual(AudioTransitionStyle.fadeOutIn(out: 0.3, in: 0.25).inDuration, 0.25)

        XCTAssertEqual(AudioTransitionStyle.musicCrossfade(duration: 2).outDuration, 2)
        XCTAssertEqual(AudioTransitionStyle.musicCrossfade(duration: 2).inDuration, 2)
    }
}
