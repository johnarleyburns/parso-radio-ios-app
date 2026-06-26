import Foundation

/// Why playback is moving from one item to the next. The view model owns the
/// reason (it knows the navigation path); the policy maps it — together with the
/// outgoing/incoming media kinds — to an `AudioTransitionStyle`.
enum PlaybackTransitionReason: Equatable, Sendable {
    case naturalAdvance
    case manualNext
    case manualPrevious
    case channelChange
    case playlistChange
    case directItemChange
    case searchAudition
    case retryAfterFailure
    case nonAudioSkip
    case stallSkip
    case stop
    case sleepTimer
    case resume
}

/// How the audio layer should move between items. Phase 1 ships single-player
/// fade-out/fade-in only — there is no true overlap. `musicCrossfade` is reserved
/// for a Phase 2 dual-player implementation and is never emitted by the Phase 1
/// policy; the audio engine treats it as a fade-in if it ever sees one.
enum AudioTransitionStyle: Equatable, Sendable {
    case immediate
    case fadeIn(duration: TimeInterval)
    case fadeOut(duration: TimeInterval)
    case fadeOutIn(out: TimeInterval, in: TimeInterval)
    case musicCrossfade(duration: TimeInterval) // Phase 2 only

    /// Duration of the outgoing (fade-out) portion, if any. Used by `skip`.
    var outDuration: TimeInterval? {
        switch self {
        case .immediate, .fadeIn: return nil
        case let .fadeOut(d): return d > 0 ? d : nil
        case let .fadeOutIn(out, _): return out > 0 ? out : nil
        case let .musicCrossfade(d): return d > 0 ? d : nil
        }
    }

    /// Duration of the incoming (fade-in) portion, if any. Used by `play`.
    var inDuration: TimeInterval? {
        switch self {
        case .immediate, .fadeOut: return nil
        case let .fadeIn(d): return d > 0 ? d : nil
        case let .fadeOutIn(_, inn): return inn > 0 ? inn : nil
        case let .musicCrossfade(d): return d > 0 ? d : nil
        }
    }
}

/// Pure resolver mapping (outgoing kind, incoming kind, reason, context) to an
/// `AudioTransitionStyle`. Knows nothing about AVPlayer, network, the database,
/// or SwiftUI — fully unit-tested via `PlaybackTransitionPolicyTests`.
///
/// Phase 1 rules (see plans/playback-transitions): no true crossfade when either
/// side is audiobook, lecture, podcast, or ambient; spoken boundaries are never
/// overlapped; explicit user switches fade out promptly; recovery paths are
/// immediate.
struct PlaybackTransitionPolicy {

    static func isSpoken(_ kind: MediaKind) -> Bool {
        switch kind {
        case .audiobook, .lecture, .podcast: return true
        case .music, .ambient: return false
        }
    }

    func style(from outgoing: MediaKind?,
               to incoming: MediaKind?,
               reason: PlaybackTransitionReason,
               sameWork: Bool = false,
               looping: Bool = false,
               crossfadeMusic: Bool = false) -> AudioTransitionStyle {
        // Reliability and correctness beat smoothness on recovery / teardown /
        // non-audible paths.
        switch reason {
        case .retryAfterFailure, .nonAudioSkip, .stallSkip, .stop, .resume:
            return .immediate
        case .sleepTimer:
            // Wall-clock sleep expiry fades out gently before pausing. Executed
            // by SleepTimerController via fadeOutThenPause.
            return .fadeOut(duration: 10)
        default:
            break
        }

        guard let incoming else { return .immediate }

        // Ambient is a loop surface, never a track-to-track queue: gentle onset
        // on the way in, sequential fade (no overlap) on the way out.
        if incoming == .ambient || looping {
            return .fadeIn(duration: 0.8)
        }
        if outgoing == .ambient {
            return .fadeOutIn(out: 0.5, in: 0.25)
        }

        let outSpoken = outgoing.map(Self.isSpoken) ?? false
        let incSpoken = Self.isSpoken(incoming)

        // Cross-media (one side spoken, the other music): clarity, never overlap.
        if let outgoing, outgoing != incoming, outSpoken != incSpoken {
            return reason == .naturalAdvance
                ? .immediate
                : .fadeOutIn(out: 0.30, in: 0.25)
        }

        // Incoming spoken (audiobook / lecture / podcast).
        if incSpoken {
            switch reason {
            case .naturalAdvance:
                // Chapter / episode / work boundaries stay intact — no overlap,
                // no trim — whether or not it is the same work.
                return .immediate
            case .manualNext, .manualPrevious, .channelChange,
                 .playlistChange, .directItemChange, .searchAudition:
                return .fadeOutIn(out: 0.2, in: 0.2)
            default:
                return .immediate
            }
        }

        // Music → music.
        switch reason {
        case .naturalAdvance:
            // Phase 2: true overlap crossfade when the user has it enabled (music
            // radio channels). Otherwise the Phase 1 short fade-in from silence.
            return crossfadeMusic
                ? .musicCrossfade(duration: 2.0)
                : .fadeIn(duration: 0.2)
        case .manualNext, .manualPrevious:
            return .fadeOutIn(out: 0.25, in: 0.25)
        case .channelChange, .playlistChange, .directItemChange, .searchAudition:
            return .fadeOutIn(out: 0.30, in: 0.25)
        default:
            return .immediate
        }
    }
}

/// Subtle, context-preserving visual transition state owned by `PlayerViewModel`
/// and consumed by `NowPlayingSheet`. Drives an artwork/tint cross-dissolve (and,
/// when the kind changes, a small icon morph) — never a stark full-screen reset.
struct PlaybackTransitionVisualState: Equatable {
    let fromKind: MediaKind?
    let toKind: MediaKind
    let reason: PlaybackTransitionReason
    let startedAt: Date
}
