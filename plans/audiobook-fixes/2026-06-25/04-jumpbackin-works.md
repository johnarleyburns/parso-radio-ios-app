# Phase 3 — Jump Back In: book/work cards + resume

**Problem.** Jump Back In shows individual chapters; tapping plays one chapter without resuming the book.

**Current behavior.** `HomeTopSection` renders `recentlyPlayedTracks(limit:)` per-track; tap → `playRecentTrack` → single track, no seek.

**Design (ASCII).**
```
HomeTopSection ──▶ recentlyPlayedWorks(limit)
  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
  │ [book cover]  │  │ [book cover]  │  │ [song cover]  │
  │ Gallipoli     │  │ Pride & Prej. │  │ Some Song     │
  │ (whole book)  │  │ (whole book)  │  │ (track)       │
  └───────────────┘  └───────────────┘  └───────────────┘
        │ tap
        ▼
  resumeWork(work):
    parts = resolveItemParts(parentIdentifier)
    (chapterId, secs) = loadPosition(playlist:album:<parentIdentifier>)
    reorder parts to start at chapterId
    playAlbumTracks(reordered, mediaKind: <persisted>, origin:.recentlyPlayed, startSeek: secs)
```
Music cards keep `playRecentTrack`.

**Data-model deltas.** None (uses Phase 0 grouping + stable key).

**Implementation steps.**
1. `RecentlyPlayedController.resumeWork(_ work:)`.
2. `HomeTopSection` consumes `RecentWork`; `JumpBackInCard` shows work title + a11y id `jumpbackin.card.book.<id>` / `.track.<id>`.
3. `ListenView` routes work taps to `resumeWork`, track taps to `playRecentTrack`.

**Testing.** Unit: `resumeWork` reorders to saved chapter and seeks. UI: one book card; tap → `player.surface.audiobook` + `player.elapsed` ≈ saved seconds (>0).

**Open questions.** Work title fallback (collectionTitle vs cleaned title).
