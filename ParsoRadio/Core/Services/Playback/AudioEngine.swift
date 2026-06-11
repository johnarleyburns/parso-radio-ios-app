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
///    torn-down item must not be delivered as the new item's progress.
@MainActor
protocol AudioEngine: AnyObject {
    var isPlaying: Bool { get }
    var duration: Double? { get }
    var playbackRate: Float { get }
    var repeatMode: AudioPlayerService.RepeatMode { get set }
    var isAuditioning: Bool { get set }
    var throttleTimer: Bool { get set }

    var onReady: ((Double) -> Void)? { get set }
    var onTimeUpdate: ((Double) -> Void)? { get set }
    var onTrackFinished: (() -> Void)? { get set }
    var onPreviousTrack: (() -> Void)? { get set }
    var onNonAudio: (() -> Void)? { get set }

    func play(url: URL, track: Track, looping: Bool, startAt: Double, autoPlay: Bool)
    func pause()
    func resume()
    func seek(to seconds: Double)
    func skip()
    func setContentMode(_ mode: AudioPlayerService.ContentMode)
    func setPlaybackRate(_ rate: Float)
    func syncPlaybackState()
    func invalidateStreamingCache(for trackID: String)
    func updateNowPlayingArtwork(_ artwork: UIImage)
    func updateNowPlayingChannel(_ channelName: String)
}
