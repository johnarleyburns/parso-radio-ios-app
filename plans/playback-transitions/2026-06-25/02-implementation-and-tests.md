# Implementation And Tests

## Problem

The risky part is not fading volume. The risky part is preserving the playback invariants that already protect Lorewave: latest-wins async loads, exact resume positions, no stale ticks from torn-down players, no playlist double-teardown, spoken resume persistence, and stable ambient loops.

## Current Behavior

Relevant files:

- `ParsoRadio/Core/Services/Playback/AudioEngine.swift`
- `ParsoRadio/Core/Services/Playback/AudioPlayerService.swift`
- `ParsoRadio/ViewModels/PlayerViewModel.swift`
- `ParsoRadio/Core/Services/Playback/PlaylistPlaybackController.swift`
- `ParsoRadio/Core/Services/Playback/WholeItemController.swift`
- `ParsoRadio/Core/Services/Playback/SleepTimerController.swift`
- `ParsoRadio/Core/Tests/FakeAudioEngine.swift`
- `ParsoRadio/Core/Tests/PlaybackReliabilityTests.swift`
- `ParsoRadio/Core/Tests/PlayerViewModelTests.swift`

Important current invariants:

- `PlayerViewModel` is `@MainActor`.
- `playbackContextToken` invalidates stale context loads.
- `StallModel` load generations prevent rapid skip/back races.
- `AudioPlayerService` uses `playToken` to block stray time ticks from old players.
- Playlist loading has a regression test ensuring it does not call extra `skip()` before `playTrack(...)`.
- Ambient loop playback has a regression test preventing the old crashing `AVAudioEngine` loop backend from coming back.

## Implementation Steps

1. Add transition model and policy.

Create a pure model file such as `ParsoRadio/Core/Services/Playback/PlaybackTransition.swift`, or put the small types near `MediaKind` if the team prefers fewer files.

Add tests first for the policy table:

- music manual next -> short `fadeOutIn`
- music natural -> Phase 1 fade-in or immediate
- audiobook same-work natural -> immediate
- podcast natural -> immediate
- spoken/manual -> short `fadeOutIn`
- mixed music/spoken -> no crossfade
- ambient -> fade only on start/stop/sleep, no crossfade
- failure/stall/non-audio -> immediate

2. Extend `AudioEngine` carefully.

Recommended protocol shape:

```swift
func play(url: URL,
          track: Track,
          looping: Bool,
          startAt: Double,
          autoPlay: Bool,
          transition: AudioTransitionStyle)

func skip(transition: AudioTransitionStyle)
```

Keep compatibility manageable by adding default convenience methods in an extension if useful, but update all call sites explicitly during implementation so the transition reason is visible in code review.

Update `FakeAudioEngine` to capture:

- `lastTransition`
- `skipTransitions`
- `playTransitions`

3. Implement fades in `AudioPlayerService` without changing playback semantics.

Add a cancellable `transitionTask` and cancel it from every new `play`, `skip`, `tearDownPlayer`, route interruption, and failure path.

Use `AVPlayer.volume` for Phase 1 fades. Keep it simple:

- outgoing fade in 30-60 ms ticks on the main actor
- clamp volume to `[0, 1]`
- always restore volume to `1.0` after teardown or after a fade-in completes
- for `autoPlay == false`, do not fade in or call `play()`
- for looping ambient, fade player volume only; do not replace `AVPlayerLooper`

Suggested internal helpers:

```swift
private func fadeCurrentPlayer(to target: Float, duration: TimeInterval) async
private func playAfterOutgoingFade(...)
private func startNewPlayerAtZeroThenFadeIn(...)
```

Do not call `onTrackFinished` from a fade-driven skip. Remote command next can still intentionally call the view model's next path, but fade teardown itself must not look like a natural finish.

4. Split visual preparation from audio teardown.

`PlayerViewModel.beginTransition(pre:)` currently calls `audioPlayer.skip()`. Replace it with two concepts:

- `prepareVisualTransition(pre:reason:)`: clears stale UI synchronously and sets loading/pre-track metadata.
- `stopCurrentAudio(reason:)` or transition-aware `playTrack(... reason:)`: passes the audio transition to `AudioEngine`.

This matters because playlist loading already had a regression around double teardown. Do not add a new skip-before-play path.

5. Thread transition reason through playback entry points.

Recommended call-site changes:

- `onTrackFinished` -> `advanceToNext(reason: .naturalAdvance)`
- `skip()` -> `.manualNext`
- `goToPreviousTrack()` / `playPreviousTrack()` -> `.manualPrevious`
- `load(channel:)` -> `.channelChange`
- `loadPlaylist(...)` -> `.playlistChange`
- `playSingleTrack`, `playAlbumTracks`, `playSequentialItem`, recent-work resume -> `.directItemChange` or `.resume`
- `auditionTrack` / `playSearchResult` -> `.searchAudition`
- `handleLoadFailure` / stall / non-audio -> `.retryAfterFailure`, `.stallSkip`, `.nonAudioSkip`
- sleep timer wall-clock expiry -> `.sleepTimer`

Capture outgoing kind before assigning `currentTrack = track`. For direct and playlist contexts, prefer `currentTrack?.mediaKind(in: currentChannel) ?? activeMediaKind` for the outgoing side and `track.mediaKind(in: currentChannel)` for incoming.

6. Preserve prefetch and improve it only after Phase 1 is stable.

Phase 1 can keep `prefetchNextURL(channel:)`. Extend it to playlists only if it is straightforward and testable.

Phase 2 true music crossfade requires more than a URL cache. It needs one of:

- a second `AVPlayer` prepared with the next item, or
- an `AVQueuePlayer` path for non-looping music with known next item, or
- a carefully isolated dual-player service used only for music-to-music natural advance.

Do not do Phase 2 inside the first fade patch unless the team explicitly accepts the larger blast radius.

7. Update sleep timer behavior.

`SleepTimerController.startSleepTimer(minutes:)` currently sleeps until the end time, then pauses immediately. For wall-clock timers:

- if remaining time is greater than fade duration, wake `8-12` seconds early and call fade-out pause
- if the user cancels, restore volume and cancel the fade task
- if `sleepAtEndOfTrack` is used, keep current behavior: pause at natural boundary, no crossfade or trim

8. Add visual transition state.

Keep this lightweight. The first implementation can animate only the artwork/gradient and dominant tint. The media-kind icon morph can follow after the audio policy lands.

Do not remove the existing immediate stale-state clearing required by tests. Instead, replace the stark empty moment with a deliberate placeholder/tint transition.

## Testing Strategy

Unit tests:

- `PlaybackTransitionPolicyTests` for the full matrix.
- `FakeAudioEngine` assertions that `PlayerViewModel.skip()` passes `.manualNext` and not `.immediate` for music.
- Playlist loading still has `engine.skipCount == 0` before first `play()`.
- Spoken natural next part passes a non-overlap style.
- Mixed playlist music -> audiobook suppresses crossfade.
- Stall/non-audio paths pass `.immediate` and still advance/give up correctly.
- Sleep timer wall-clock expiry calls fade pause; end-of-track sleep does not.

Audio service tests:

- Fading skip does not invoke `onTrackFinished`.
- Fade cancellation restores volume to `1.0`.
- `autoPlay: false` does not start audio during fade-in.
- Ambient looping play/pause/skip still does not crash and stays on `AVPlayerLooper`.

UI/view tests:

- `NowPlayingSheet` renders the correct surface for each `activeMediaKind` while transition state is active.
- Reduce Motion path uses opacity-only transition.
- Media-kind change exposes the new title/kind to accessibility via existing labels, with no duplicate announcement-only text.

Manual QA:

- Music channel: manual next, previous, natural advance, shuffle on/off.
- Podcast channel: finish episode, manual episode selection, skip -15/+30, speed, sleep timer.
- Audiobook: resume mid-chapter, finish chapter into next part, next/previous book from overflow, sleep-at-end.
- Lecture: same as audiobook, including work time left.
- Ambient: start, pause, sleep timer fade, loop for at least two minutes, background/lock screen.
- Mixed For You or mixed playlist: music -> audiobook, audiobook -> music, podcast -> music, music -> music.
- Poor network: manual next during slow IA URL resolution should not leave old audio playing indefinitely.

Build command:

```sh
xcodebuild -project ParsoMusic.xcodeproj -scheme ParsoMusic -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' build
```

Run targeted tests first, then the full test target if time allows:

```sh
xcodebuild -project ParsoMusic.xcodeproj -scheme ParsoMusic -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' test -only-testing:ParsoMusicTests/PlaybackReliabilityTests
```

## Risks

- Fade tasks can race with rapid skip/back/channel changes unless they are cancelled on every new load and tied to the same latest-wins assumptions as playback.
- A fade-out before a slow network load can create silence. That is acceptable for explicit user switches, but natural advance should rely on prefetch and future prepared-next work.
- True crossfade may conflict with remote command, Now Playing, and background audio behavior if implemented with two players. Keep it music-only and Phase 2.
- Volume restoration bugs can leave future tracks quiet. Tests must assert volume reset.
