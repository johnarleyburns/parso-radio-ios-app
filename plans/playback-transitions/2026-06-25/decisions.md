# Decisions

- Do not implement a universal crossfade. Lorewave is a mixed media player, and spoken-word media should not overlap.
- Phase 1 should use single-player fade-out/fade-in transitions. True overlap crossfade is Phase 2 and music-to-music only.
- Explicit user switches should fade out promptly. Natural auto-advance should prioritize prefetch/prepared playback and avoid unnecessary silence.
- Preserve spoken boundaries. Audiobook chapters, lecture parts, podcast episodes, and work changes should not be trimmed or overlapped.
- Preserve the ambient loop architecture. Keep bundled pre-crossfaded loop assets and `AVPlayerLooper`; do not reintroduce the prior crashing `AVAudioEngine` loop backend.
- Transition policy should be a pure tested resolver based on outgoing kind, incoming kind, reason, and context. Audio service should execute styles; view model should choose reasons.
- Visual transitions should be subtle and context-preserving: artwork/tint cross-dissolve and optional media-kind icon morph, with Reduce Motion support.
- Failure, stall, retry, non-audio, interruption, and destructive data-clear paths stay immediate.
