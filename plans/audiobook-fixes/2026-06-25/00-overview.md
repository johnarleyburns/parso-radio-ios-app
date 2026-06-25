# Audiobook UX Fixes — Overview

Date: 2026-06-25

## Raw notes / reported symptoms

User searched the audiobook "gallipoli" and reported four problems:

1. No "add to favorites" button appeared on the search result for the book.
2. Every chapter was listed three times in a row (chapter 1, chapter 1, chapter 1, then the next part, etc.).
3. "Jump Back In" shows the individual chapter/track, not the book; tapping should resume the book at the most recent saved position.
4. The app sometimes shows the wrong now-playing surface (music surface instead of book surface). A chapter and a music track must NEVER be conflated in the UI.

## Design principles

- **Database is the source of truth.** Schema changes are additive only (nullable/defaulted columns, `addColumnIfNotExists`).
- **Media kind must be authoritative and persisted**, not re-derived from a context-free `Track` (re-derivation returns `.music` for a book chapter when `channel == nil`).
- **One stable identity per work.** Books/lectures/podcasts resume from a stable, parent-identifier-derived position key — never a random UUID.
- Core logic lives in headlessly testable layers (DatabaseService, InternetArchiveService, controllers); SwiftUI views stay thin.
- Every fix ships with a failing-before / passing-after test. UI tests are the acceptance gate; unit tests are the engine gate.

## Root causes (file-grounded)

| # | Root cause | Location |
|---|-----------|----------|
| 1 | `FavoriteButton` exists only in player controls; `ItemDetailView` and search rows have none | `Views/Search/ItemDetailView.swift`, `Views/SearchView.swift:206` |
| 2 | `fetchTracksForIdentifier` never dedupes multiple MP3 bitrate variants per chapter; `partsAreClean` passes because dupes get sequential part numbers | `Core/Services/API/InternetArchiveService.swift:390-440`, `ViewModels/PlayerViewModel.swift:1351` |
| 3 | History is track-level (`fetchRecentlyPlayedTracks` dedupes by `track_id` only); tap = `playTrack(seekTo:nil)`; book playback uses random `album:<UUID>` position key | `Core/Services/Storage/DatabaseService.swift:1001`, `Core/Services/Playback/RecentlyPlayedController.swift:17`, `Core/Services/Playback/WholeItemController.swift:114` |
| 4 | Media kind never persisted; `Track.mediaKind(in:nil)` returns `.music` for a book chapter; `playSearchResult` hardcodes `.music` | `Core/Models/MediaKind+Resolve.swift:19`, `ViewModels/PlayerViewModel.swift:1733` |

## Cross-cutting foundation

The deepest defect (driving #3 and #4) is that **media kind is never stored with a play**. Foundation:

- Additive `media_kind TEXT` column on `track_play_history`.
- `recordPlayed(channelId:trackId:mediaKind:)` persists `activeMediaKind` at play time.
- `fetchRecentlyPlayedWorks(limit:)` collapses book/lecture/podcast chapters under their `parentIdentifier` (one card per work), keeps music per-track.
- `playAlbumTracks` uses a stable `album:<parentIdentifier>` playlist id so the position key (`playlist:album:<parentIdentifier>`) is resumable across entry points.

## Roadmap (phased, one PR each)

| Phase | Branch (stacks on) | Scope |
|------|--------------------|-------|
| 0 | `fix/foundation-mediakind-history` (main) | media_kind column, recordPlayed, fetchRecentlyPlayedWorks, stable album key, UITest seam, a11y ids |
| 1 | `fix/chapter-dedup` (0) | fetch-layer dedup + partsAreClean hardening |
| 2 | `fix/surface-kind` (1) | persisted-kind PlaybackContext, playSearchResult fix, source guards |
| 3 | `fix/jumpbackin-works` (2) | work cards + resumeWork + tap routing |
| 4 | `fix/search-favorites` (0) | favorite in ItemDetailView + search row swipe |

See `decisions.md` for settled product decisions and `current_state.md` for live status.
