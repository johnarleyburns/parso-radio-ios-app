# Phase 2 — Surface kind correctness

**Problem.** Music surface renders for a book; chapter and music track get conflated.

**Current behavior.** `playRecentTrack` and `playAlbumTracks` use `track.mediaKind(in: nil)` (returns `.music` for a context-free book chapter). `playSearchResult` hardcodes `mediaKind: .music`.

**Design.**
```
resume/recent context.mediaKind = persisted play-history kind (Phase 0)
playSearchResult(group, mediaKind) — kind threaded from SearchView.handleTap
                                     (bookish collection / ItemKind → .audiobook)
RegressionContractSourceTests: ban  `mediaKind: .music`  hardcode in playSearchResult
```

**Data-model deltas.** None.

**Implementation steps.**
1. `RecentlyPlayedController.playRecentTrack` / `resumeWork` build context from persisted kind.
2. `playSearchResult(_:mediaKind:)` additive param; `SearchView.handleTap` passes derived kind.
3. New source-guard tests.

**Testing.** Unit: context kind == persisted kind. Source guard fails on the banned hardcode. UI: tapping the book opens `player.surface.audiobook` with SpokenControls.

**Open questions.** None.
