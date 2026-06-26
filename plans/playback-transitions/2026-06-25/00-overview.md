# Playback Transitions Handoff

Date: 2026-06-25  
Repo: `parso-radio-ios-app` / Lorewave  
Status: plan only; no implementation in this handoff

## Problem

Lorewave is a combined music, audiobook, lecture, podcast, and ambient player. The current transition behavior is mostly a hard cut: the old `AVPlayer` is torn down before the next item is ready, and the UI clears artwork/time immediately. That is acceptable for failures, but it feels abrupt for normal listening and can create dead air during network URL resolution.

A single crossfade rule would be wrong here. Music apps use crossfade, gapless playback, and DJ-style transitions, but audiobook and podcast players preserve spoken boundaries and center controls around skip-by-seconds, speed, chapters/episodes, sleep, and queue management. Lorewave needs a media-kind-aware transition policy, not a rubber-stamped music crossfade.

## Current Behavior

`ParsoRadio/Core/Services/Playback/AudioEngine.swift` defines `play(...)` and `skip()` as teardown-style operations. Its timing contract explicitly says `skip()` and `play()` tear down the previous item.

`ParsoRadio/Core/Services/Playback/AudioPlayerService.swift` implements that contract: `play(...)` calls `tearDownPlayer()` immediately, builds a new `AVPlayerItem`, and only starts playback once the item is ready enough. `skip()` tears down and clears Now Playing.

`ParsoRadio/ViewModels/PlayerViewModel.swift` has several transition paths:

- Natural end: `onTrackFinished` calls `advanceToNext()`.
- Manual next: `skip()` saves autosave, calls `audioPlayer.skip()`, sets loading state, then advances.
- Channel switch: `load(channel:)` autosaves, calls `audioPlayer.skip()`, clears state, then fetches/plays.
- Search/audition: `beginTransition(pre:)` calls `audioPlayer.skip()` before `playTrack(...)` resolves the URL.
- Look-ahead: `prefetchNextURL(channel:)` resolves a candidate Internet Archive URL after a track starts, but only caches a URL, not a prepared player item.

Ambient loops already have special handling. Bundled WAV loops are preprocessed with a tail-to-head equal-power crossfade and played through `AVPlayerLooper`. There is also a regression test stating an earlier `AVAudioEngine` crossfade backend crashed on ambient-loop channels. Do not reintroduce that path for ambient.

## Research Signal

Apple Music treats song transitions as a music-specific feature: iOS 26 supports AutoMix and Crossfade, and Apple notes that AutoMix selects transitions based on the music, may remove silence, may use a simple crossfade, and that albums and some genres play without transitions. Source: [Apple Support, Transition songs in Music on iPhone](https://support.apple.com/guide/iphone/transition-songs-iphadf2fe1f4/ios).

Spotify exposes three separate music transition tools: Crossfade overlaps two tracks by fading out one while fading in the next, Automix offers beat-matched transitions on select playlists, and Gapless playback removes pauses between tracks. Source: [Spotify Support, Transitions between tracks](https://support.spotify.com/us/article/tracks-transitions/).

Apple Music queue behavior separates queue management from transitions. Users can Play Next, Add to Queue, reorder/remove items, and AutoPlay adds similar songs at the end of the queue; the queue also exposes transition toggles. Source: [Apple Support, Queue up your music on iPhone](https://support.apple.com/guide/iphone/queue-up-your-music-ipha4521ef7d/ios).

Apple Podcasts does not present crossfade as a podcast affordance. The Now Playing controls focus on scrub-to-time, playback speed, Enhance Dialogue, skip back 15 seconds, skip forward 30 seconds, sleep timer, chapters when available, AirPlay, queue, and transcript/media links. Source: [Apple Support, Watch and listen to podcasts on iPhone](https://support.apple.com/guide/iphone/watch-and-listen-to-podcasts-iph3a22707a5/ios).

Apple Books audiobooks likewise center spoken-word controls: skip forward/back with rounded arrows, configurable skip lengths, scrubber, narration speed, sleep timer, AirPlay, and chapters. Source: [Apple Support, Listen to audiobooks in Books on iPhone](https://support.apple.com/guide/iphone/listen-to-audiobooks-iphac1971248/ios).

Apple's 2025 design direction emphasizes content focus, familiar controls, thoughtful grouping, and materials that transform based on content/context. That supports a gentle transition indicator, not a jarring full-screen reset. Source: [Apple Newsroom, new software design](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/).

## Recommendation

Implement transitions in two phases.

Phase 1 should add a policy-driven fade system using the existing single-player architecture:

- Music-to-music manual next/previous: short fade-out, load next, short fade-in.
- Music natural auto-advance: keep the existing prefetch path and add a very short fade-in only if the next item starts from silence.
- Spoken media natural advance: no overlap and no crossfade. Preserve chapter, episode, and work boundaries.
- Spoken manual navigation: optional 150-250 ms fade-out/fade-in with no overlap.
- Podcast episode auto-advance: no overlap, no intro/outro trimming, no crossfade.
- Ambient: keep `AVPlayerLooper` and preprocessed loop assets; add start/sleep fade only.
- Mixed playlists and mixed For You: if either outgoing or incoming item is spoken, use the spoken policy. Crossfade only when both sides are music.
- Errors, non-audio skips, stall recovery, route interruptions, and clear-all-data: immediate teardown.

Phase 2 can add true overlap crossfade only for music-to-music natural advance. That likely needs a dual-player or prepared-next-item architecture. Do not attempt true crossfade for speech, ambient loops, or cross-media-kind transitions.

## Design

Add a pure `PlaybackTransitionPolicy` that maps outgoing media kind, incoming media kind, transition reason, and context to an `AudioTransitionStyle`. `PlayerViewModel` decides the transition reason; `AudioPlayerService` executes the audio fade. This keeps recommendation logic, queue logic, and audio mechanics separated.

ASCII flow:

```text
User / Engine event
      |
      v
PlayerViewModel captures outgoing track + reason
      |
      v
PlaybackTransitionPolicy.resolve(fromKind, toKind, reason)
      |
      +--> visual transition state for NowPlayingSheet
      |
      v
AudioEngine.play(url, track, ..., transition: style)
      |
      v
AudioPlayerService fades or tears down according to style
```

For visual transitions, add a small `PlaybackTransitionVisualState` rather than clearing from old artwork to a stark empty surface. The visual should be subtle: cross-dissolve artwork or category gradient, interpolate dominant tint, and show a compact media-kind icon change only when the kind changes. Respect Reduce Motion by using opacity only. Do not add explanatory text or a modal; the transition should communicate context without interrupting listening.

## Acceptance Criteria

- No true crossfade is applied when either side is audiobook, lecture, podcast, or ambient.
- Music manual next/previous has no hard click and no old track bleeding after the user explicitly requested a switch.
- Natural spoken chapter/episode/work boundaries remain intact; no narration is overlapped or trimmed.
- Existing `playbackContextToken`, stall-generation, and latest-wins protections remain effective during fades.
- Playlist load regression remains fixed: loading a playlist must not call an extra `skip()` before `playTrack(...)`.
- Ambient loop playback continues using bundled loop assets plus `AVPlayerLooper`; no `AVAudioEngine` loop crossfade is added.
- Sleep timer wall-clock expiry fades out gently before pausing; sleep-at-end-of-track still pauses at the boundary.
- Fake engine tests can assert transition styles without real audio.

## Open Questions

- Should music natural auto-advance get true overlap crossfade in this release, or should Phase 1 ship with fade-out/fade-in only and leave true crossfade for a later dual-player implementation?
- Should podcast episode-to-episode auto-advance insert a tiny respectful gap, or should it remain immediate after finish like Apple Podcasts queue behavior?
- Should crossfade become a user setting, or should Lorewave start with fixed app-chosen defaults and expose settings only after real listening tests?
