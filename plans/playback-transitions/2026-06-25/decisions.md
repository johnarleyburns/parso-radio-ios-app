# Decisions

- Do not implement a universal crossfade. Lorewave is a mixed media player, and spoken-word media should not overlap.
- Phase 1 should use single-player fade-out/fade-in transitions. True overlap crossfade is Phase 2 and music-to-music only.
- Explicit user switches should fade out promptly. Natural auto-advance should prioritize prefetch/prepared playback and avoid unnecessary silence.
- Preserve spoken boundaries. Audiobook chapters, lecture parts, podcast episodes, and work changes should not be trimmed or overlapped.
- Preserve the ambient loop architecture. Keep bundled pre-crossfaded loop assets and `AVPlayerLooper`; do not reintroduce the prior crashing `AVAudioEngine` loop backend.
- Transition policy should be a pure tested resolver based on outgoing kind, incoming kind, reason, and context. Audio service should execute styles; view model should choose reasons.
- Visual transitions should be subtle and context-preserving: artwork/tint cross-dissolve and optional media-kind icon morph, with Reduce Motion support.
- Failure, stall, retry, non-audio, interruption, and destructive data-clear paths stay immediate.

## Phase 2 (resolved 2026-06-25)

- True overlap crossfade ships in Phase 2, **music→music natural auto-advance only**. Manual next/previous keeps the Phase 1 fade-out/in; spoken, ambient, and cross-media transitions never overlap.
- Crossfade is exposed as a **Settings toggle, default ON** (`musicCrossfadeEnabled`). Phase 1 fades remain the fallback when the toggle is off (or when an overlap can't be prepared in time).
- Crossfade duration is a **fixed 2.0 s** equal-power-ish ramp.
- Scope is **music radio channels** (`currentChannel?.mediaKind == .music`). Music playlists / mixed For-You keep the Phase 1 fade-in for now (their next item can be spoken; channel pools are reliably music). Revisit playlist crossfade after channel crossfade proves out.
- Architecture: keep the single primary `AVPlayer`, but on a music-channel track the engine fires the natural-advance trigger ~2 s **before** the real end (the crossfade lead) so the outgoing track is still audible; the incoming `.musicCrossfade` play demotes the still-playing outgoing to a second player, ramps it down while ramping the new one up, then tears the outgoing down. No `AVQueuePlayer`/`AVAudioEngine` rewrite. If the next item can't be ready within the lead (slow resolve), it cleanly degrades to a Phase 1 fade-in.
