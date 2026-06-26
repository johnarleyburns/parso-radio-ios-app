# Current State

2026-06-25: Investigation and handoff plan written. No code changes were made for this transition work.

2026-06-25 (later): Phase 1 implemented and verified (`ParsoMusicTests` green, 764 tests).

Phase 1 delivered:

- `Core/Services/Playback/PlaybackTransition.swift` — pure `PlaybackTransitionReason`, `AudioTransitionStyle` (with `outDuration`/`inDuration` accessors), `PlaybackTransitionPolicy`, and `PlaybackTransitionVisualState`. No AVPlayer/network/SwiftUI dependencies.
- `AudioEngine` protocol now exposes `play(..., transition:)`, `skip(transition:)`, and `fadeOutThenPause(duration:)`, with `.immediate` convenience overloads so unchanged call sites keep working.
- `AudioPlayerService` executes fades via a single cancellable `transitionTask` + `ramp(...)` on `AVPlayer.volume`: fade-in on a new item, fade-out-then-teardown on skip, and sleep fade-out-then-pause. The task is cancelled (volume restored to 1.0) on every play/skip/teardown/pause/resume/route-loss/interruption. Ambient stays on `AVPlayerLooper`; no `AVAudioEngine` loop backend.
- `PlayerViewModel.playTrack` resolves the media-kind-aware style before `currentTrack` is reassigned and threads a `reason:` through every entry point (natural advance, manual next/previous, channel/playlist/direct/search, recovery). `beginTransition(pre:reason:)` is now fade-aware. `transitionVisualState` is published for the UI.
- `SleepTimerController` wakes ~10 s early for wall-clock timers and fades out before pausing; cancel mid-fade restores full volume. End-of-track sleep still pauses at the boundary (no fade).
- `NowPlayingSheet` cross-dissolves artwork per track (keyed on track id), Reduce-Motion-aware (instant, opacity-only).
- Tests: `PlaybackTransitionPolicyTests` (full matrix + style accessors) and `PlaybackTransitionOrchestrationTests` (policy reaches the engine via the VM; playlist load still does `skipCount == 0`; sleep fade seam). `FakeAudioEngine` captures `playTransitions`/`skipTransitions`/`fadeOutPauseCount`.

Plan files:

- `00-overview.md`
- `01-transition-policy.md`
- `02-implementation-and-tests.md`
- `decisions.md`

Important repo state observed during planning:

- The working tree already had unrelated modified and untracked files before these plan files were added. Do not revert them as part of this work.
- Ambient loops already use bundled loop assets plus `AVPlayerLooper`; an earlier `AVAudioEngine` loop crossfade path is covered by a crash regression test and should not return.
- `FakeAudioEngine` is the right place to capture transition styles for orchestration tests.

Next step: Phase 2 (true overlap music-to-music crossfade) remains future work and requires a dual-player / prepared-next-item architecture. Phase 1 ships single-player fade-out/fade-in only. Manual QA on device for fade feel (music next/prev, spoken boundaries, ambient onset, sleep fade) is still recommended.
