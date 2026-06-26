import Foundation
import UIKit

/// The audio playback surface `PlayerViewModel` drives. Extracted so the
/// orchestrator can be tested against a deterministic `FakeAudioEngine` (the
/// real `AudioPlayerService` wraps AVPlayer and can't run off-device).
///
/// Timing contract a conforming engine MUST honor (the fake models exactly
/// this, the real one must match it):
///  - After `play(autoPlay:true)`, it eventually calls `onReady(duration)` once
///    the item is playable, then `onTimeUpdate(seconds)` repeatedly while audio
///    actually progresses (NEVER while stalled/buffering).
///  - A track that can never play emits NO `onTimeUpdate` (the orchestrator's
///    stall watchdog is what gives up — the engine does not self-skip).
///  - `onTrackFinished` fires once when a track plays to its natural end.
///  - `skip()`/`play()` tear down the previous item; stray ticks from a
///    torn-down item must not be delivered as the new item's progress. A
///    transition style with a fade-out portion MAY defer the actual teardown
///    until the fade completes, but a subsequent `play`/`skip` always wins
///    (latest-wins) and force-tears-down immediately.
@MainActor
protocol AudioEngine: AnyObject {
    var isPlaying: Bool { get }
    var duration: Double? { get }
    var playbackRate: Float { get }
    var repeatMode: AudioPlayerService.RepeatMode { get set }

    var onReady: ((Double) -> Void)? { get set }
    var onTimeUpdate: ((Double) -> Void)? { get set }
    var onTrackFinished: (() -> Void)? { get set }
    var onPreviousTrack: (() -> Void)? { get set }
    var onNonAudio: (() -> Void)? { get set }
    var onPlaybackFailure: (() -> Void)? { get set }

    func play(url: URL, track: Track, looping: Bool, startAt: Double, autoPlay: Bool,
              transition: AudioTransitionStyle)
    func pause()
    func resume()
    func seek(to seconds: Double)
    func skip(transition: AudioTransitionStyle)
    /// Wall-clock sleep-timer expiry: fade the current player to silence over
    /// `duration`, then pause (restoring full volume for the next resume). Does
    /// NOT tear down the item — the user can resume exactly where they faded out.
    func fadeOutThenPause(duration: TimeInterval)
    func setContentMode(_ mode: AudioPlayerService.ContentMode)
    func setPlaybackRate(_ rate: Float)
    func syncPlaybackState()
    func invalidateStreamingCache(for trackID: String)
    func updateNowPlayingArtwork(_ artwork: UIImage)
    func updateNowPlayingChannel(_ channelName: String)
}

extension AudioEngine {
    /// Convenience for the many call sites that don't choose a transition: an
    /// immediate (hard) load/teardown, matching the legacy behavior.
    func play(url: URL, track: Track, looping: Bool, startAt: Double, autoPlay: Bool) {
        play(url: url, track: track, looping: looping, startAt: startAt,
             autoPlay: autoPlay, transition: .immediate)
    }
    func skip() { skip(transition: .immediate) }
}

