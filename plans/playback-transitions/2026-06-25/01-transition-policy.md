# Transition Policy

## Problem

The app currently treats most playback changes as the same operation: stop the old `AVPlayer`, clear UI, resolve/load the next URL, and start. That erases the differences between music radio, spoken sequential listening, podcasts, whole-work playback, mixed playlists, and ambient loops.

## Current Behavior

`MediaKind` already models the important product split: `.music`, `.audiobook`, `.podcast`, `.lecture`, and `.ambient`. `PlaybackContext` and `activeMediaKind` are already used to select controls and remote command mode.

Queue behavior is also kind-specific:

- Music and registry channels use shuffled pools.
- Podcasts use newest-first feed behavior.
- Audiobooks and lectures use sequential parts/works.
- Ambient uses a single-loop behavior.

The transition policy should reuse these concepts instead of adding a global crossfade flag.

## Design

Add two small model types. Exact names are flexible, but keep this shape:

```swift
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

enum AudioTransitionStyle: Equatable, Sendable {
    case immediate
    case fadeIn(duration: TimeInterval)
    case fadeOut(duration: TimeInterval)
    case fadeOutIn(out: TimeInterval, in: TimeInterval)
    case musicCrossfade(duration: TimeInterval) // Phase 2 only
}
```

Then add a pure resolver:

```swift
struct PlaybackTransitionPolicy {
    func style(from outgoing: MediaKind?,
               to incoming: MediaKind?,
               reason: PlaybackTransitionReason,
               sameWork: Bool = false,
               looping: Bool = false) -> AudioTransitionStyle
}
```

Keep the policy pure and unit-tested. It should not know about `AVPlayer`, network fetches, database state, or SwiftUI views.

## Policy Matrix

| Situation | Style | Rationale |
| --- | --- | --- |
| music -> music, natural advance | Phase 1: `fadeIn(0.15-0.25)` if next starts from silence. Phase 2: `musicCrossfade(1.5-3.0)` | Matches music-player norms while avoiding a risky dual-player rewrite in Phase 1. |
| music -> music, manual next/previous | `fadeOutIn(0.20-0.35, 0.20-0.35)` | User asked to leave the current track; do not keep old audio playing during a long load. |
| music -> music, playlist/channel/direct item switch | `fadeOutIn(0.25-0.40, 0.20-0.35)` | Smooths context change while still responding immediately. |
| audiobook/lecture same work, natural next part | `immediate` | Chapter boundaries should stay intact; do not overlap narration. |
| audiobook/lecture new work, natural advance | `immediate` or tiny visual-only breath | Preserve work boundary; no crossfade. |
| audiobook/lecture manual chapter/book/series navigation | `fadeOutIn(0.15-0.25, 0.15-0.25)` | Softens jumps without losing words or overlapping speech. |
| podcast natural next episode | `immediate` | Apple Podcasts queue plays the next episode after the previous finishes; no overlap or trim. |
| podcast manual episode/direct selection | `fadeOutIn(0.15-0.25, 0.15-0.25)` | Makes explicit jumps less abrupt while preserving episode audio. |
| any spoken -> music or music -> spoken | `fadeOutIn(0.25-0.40, 0.20-0.35)` | Cross-media changes need clarity, not overlap. |
| ambient start/resume | `fadeIn(0.70-1.00)` | Ambient loops benefit from gentle onset. |
| ambient stop/sleep timer | `fadeOut(0.80-1.50)` for explicit stop; `fadeOut(8-12)` for wall-clock sleep timer | Sleep and focus use cases should not end abruptly. |
| failure, non-audio skip, stall skip, retry, route interruption, clear all data | `immediate` | Reliability and correctness beat smoothness in recovery paths. |
| `autoPlay == false` resume/load | `immediate` for audio; visual transition only | Loading a paused item should not start audio or perform audible fades. |

## Mixed Media Rules

Mixed recommendations and mixed playlists must resolve policy from the actual outgoing and incoming tracks, not just the surface context.

Rules:

1. If either side is `.audiobook`, `.lecture`, or `.podcast`, suppress overlap crossfade.
2. Only use `musicCrossfade` when both sides are `.music`, the reason is natural advance, and Phase 2 infrastructure exists.
3. If either side is `.ambient`, never use crossfade. Ambient is a loop surface, not a track-to-track queue.
4. If the media kind changes, trigger the visual mode transition even if the audio style is short `fadeOutIn`.

## Visual Transition Policy

Add a `PlaybackTransitionVisualState` owned by `PlayerViewModel`, for example:

```swift
struct PlaybackTransitionVisualState: Equatable {
    let fromKind: MediaKind?
    let toKind: MediaKind
    let reason: PlaybackTransitionReason
    let startedAt: Date
}
```

Use it in `NowPlayingSheet` around the artwork/metadata area.

Recommended visuals:

- Same-kind music: artwork cross-dissolve and tint interpolation.
- Spoken same-work chapter advance: keep layout stable, reset progress without a flashy mode mark.
- Spoken new work or podcast episode change: subtle artwork/title cross-dissolve.
- Media-kind change: small icon/tint morph (`music.note`, `book.closed`, `waveform`, `leaf`) near the artwork for about 700 ms.
- Ambient: fade visualizer/video in/out with the audio fade.

Accessibility:

- Respect Reduce Motion. Use opacity-only transitions when enabled.
- Do not put explanatory copy on screen. VoiceOver can announce the new title/kind through existing title changes.
- Do not animate progress in a way that suggests time has moved inside the content.

## Data-Model Deltas

No database migration is needed.

Potential in-memory additions:

- `PlaybackTransitionReason`
- `AudioTransitionStyle`
- `PlaybackTransitionPolicy`
- `PlaybackTransitionVisualState`
- Optional `@Published var transitionVisualState: PlaybackTransitionVisualState?` on `PlayerViewModel`

If new Swift files are added under `ParsoRadio/`, XcodeGen's source glob should pick them up. Still run `xcodegen` if the project file is stale or the repo workflow requires it.

## Open Questions

- Should `sameWork` be derived inside `PlayerViewModel` by comparing `parentIdentifier`, playlist id, and channel id, or should it be passed by the callers that already know the navigation path?
- Should users eventually control music crossfade length, or should the first release keep fixed values for fewer settings and easier QA?
