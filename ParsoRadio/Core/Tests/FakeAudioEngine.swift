import Foundation
import UIKit
@testable import ParsoMusic

/// Deterministic `AudioEngine` for orchestrator tests. The TEST drives every
/// callback explicitly (`completeReady` / `emitTick` / `finish`) so there are no
/// real timers and tests are instant. `play()` / `skip()` are recorded so a test
/// can assert which track is live and how many loads happened (latest-wins, I6).
///
/// The one exception is the stall watchdog, which the orchestrator arms with a
/// real (tiny, injected) `Task.sleep`; a stall test simply never fires a tick.
@MainActor
final class FakeAudioEngine: AudioEngine {
    // MARK: AudioEngine surface
    private(set) var isPlaying: Bool = false
    private(set) var duration: Double?
    var playbackRate: Float = 1.0
    var repeatMode: AudioPlayerService.RepeatMode = .off

    var onReady: ((Double) -> Void)?
    var onTimeUpdate: ((Double) -> Void)?
    var onTrackFinished: (() -> Void)?
    var onPreviousTrack: (() -> Void)?

    // MARK: Observation for assertions
    private(set) var liveTrack: Track?
    private(set) var lastStartAt: Double = 0
    private(set) var lastAutoPlay: Bool = true
    private(set) var lastLooping: Bool = false
    private(set) var playCount = 0
    private(set) var skipCount = 0
    private(set) var lastSeek: Double?

    func play(url: URL, track: Track, looping: Bool, startAt: Double, autoPlay: Bool) {
        playCount += 1
        liveTrack = track
        lastStartAt = startAt
        lastAutoPlay = autoPlay
        lastLooping = looping
        duration = track.duration > 0 ? track.duration : nil
        isPlaying = autoPlay
    }
    func pause() { isPlaying = false }
    func resume() { isPlaying = true }
    func seek(to seconds: Double) { lastSeek = seconds }
    func skip() { skipCount += 1; liveTrack = nil; isPlaying = false }
    func setContentMode(_ mode: AudioPlayerService.ContentMode) {}
    func setPlaybackRate(_ rate: Float) { playbackRate = rate }
    func syncPlaybackState() {}
    func invalidateStreamingCache(for trackID: String) {}
    func updateNowPlayingArtwork(_ artwork: UIImage) {}
    func updateNowPlayingChannel(_ channelName: String) {}

    var onNonAudio: (() -> Void)?
    var onPlaybackFailure: (() -> Void)?

    // MARK: Test drivers (simulate the engine's async callbacks)

    /// Item reached `.readyToPlay`.
    func completeReady(duration: Double) {
        self.duration = duration
        onReady?(duration)
    }
    /// Audio is genuinely progressing.
    func emitTick(_ seconds: Double) { onTimeUpdate?(seconds) }
    /// Track played to its natural end.
    func finish() { isPlaying = false; onTrackFinished?() }
}
