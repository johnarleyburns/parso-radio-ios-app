# Phase 0 — Foundation: persisted media kind + work grouping + test seam

**Problem.** Media kind is not persisted with a play, and recently-played history is track-level. This blocks correct surface selection (Issue 4) and book-level Jump Back In (Issue 3). There is also no deterministic UI-test seam (launch args are dead code).

**Current behavior.** `track_play_history(channel_id, track_id, played_at)`; `recordPlayed` stores no kind; `fetchRecentlyPlayedTracks` dedupes by `track_id`. `playAlbumTracks` uses `album:<UUID>`. Splash always shows; no DB seeding hook.

**Research signal.** `addColumnIfNotExists` already used for additive migrations. `WorkKey` + `recordBookListened` already model work identity. `player.surface.*` a11y ids already exist.

**Design.**
```
recordPlayed(channelId, trackId, mediaKind?) ──▶ track_play_history.media_kind
fetchRecentlyPlayedWorks(limit) ──▶ [RecentWork]
   RecentWork { workKey, track, mediaKind, playsWholeWork }
   collapse rows where kind ∈ {audiobook,lecture,podcast} && parentIdentifier!=nil  → by parentIdentifier
   else                                                                              → by track.id
playAlbumTracks(... ) uses album id = "album:<parentIdentifier>" when shared
UITestSupport (#if DEBUG + "-uiTestSeed") seeds DB + skips splash/ToS
```

**Data-model deltas.** `ALTER TABLE track_play_history ADD COLUMN media_kind TEXT` (nullable). No destructive change.

**Implementation steps.**
1. DB: declare `colPHMediaKind`; `addColumnIfNotExists`; extend `recordPlayed`; add `fetchRecentlyPlayedWorks`.
2. Models: `RecentWork` struct.
3. `WholeItemController.playAlbumTracks` stable album id + additive `startSeek`.
4. PlayerViewModel: pass `capturedKind.rawValue` to `recordPlayed`; expose `recentlyPlayedWorks`; `bookKey` helper.
5. App: `UITestSupport.applyIfNeeded(...)` gated by launch arg; accessibility identifiers.

**Testing.** Unit: media_kind round-trips; `fetchRecentlyPlayedWorks` collapses book chapters, keeps music; migration additive. 

**Open questions.** Podcast grouping key uses parentIdentifier (feed/show) when present; otherwise per-episode.
