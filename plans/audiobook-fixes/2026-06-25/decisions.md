# Decisions (settled — do not re-litigate)

1. **Favorites affordance location (Issue 1):** Add a Favorite button to the book/album detail sheet (`ItemDetailView`) AND a swipe-to-favorite action on each search result row. (User-confirmed 2026-06-25.)

2. **Jump Back In grouping scope (Issue 3):** Audiobooks, lecture series, AND podcasts collapse into a single "work" card (resume the work). Standalone music tracks remain one card per track. Multi-track music albums are NOT collapsed. (User-confirmed 2026-06-25.)

3. **Delivery (process):** Full plans/ design docs first, then phased PRs (stacked branches, one per phase). (User-confirmed 2026-06-25.)

## Derived/implementation decisions

- **Media kind persistence:** stored in `track_play_history.media_kind` (additive, nullable). Legacy rows (null) fall back to `Track.inferredMediaKind` for grouping.
- **Stable work position key:** `playlist:album:<parentIdentifier>` via `playAlbumTracks` using a stable album playlist id derived from `ordered[0].parentIdentifier`.
- **Dedup tie-break:** highest MP3 bitrate wins (320 > 256 > 192 > VBR > 128 > 64 > generic MP3). When bitrate unknown for all variants in a group, keep the first in natural filename order.
- **Work-card title:** representative track's `collectionTitle` if present, else cleaned chapter/parent title.
