# Iterative Improvements — Fix Plan

Single batch. Every item ships together with updated + new unit/integration
tests, `swiftc -parse` validated, IA queries curl-verified, then CI driven green.

## Research findings (done before writing this plan)

- **Search too narrow (item 9).** Current query
  `(title:(Q) OR creator:(Q)) AND mediatype:audio`. IA Solr ANDs the terms
  *inside* `title:(...)`, so "Tarrega Guitar" needs both words in the **same**
  field → only 2 hits. The general default-field form `(Q) AND mediatype:audio`
  searches title/creator/description/subject/text like the IA website:
  - `(Tarrega Guitar) AND mediatype:audio` → **36** (incl. `16NarcisoYepes… —
    Narciso Yepes-Tárrega`), vs 2 today.
  - `(Narciso Yepes) AND mediatype:audio` → 52; `(bach cello)` → 420.
- **"Add entire book" broken (item 7).** `Laws_Plato` ("Laws by Plato
  (Hi-Res Audiobook)", 13h+) actually has 20 chapters but in **four** formats
  (20 VBR MP3 + 20 OGG + 20 FLAC + 20 WAVE). `fetchTracksForIdentifier`
  accepts a file if its format is preferred **or** its extension is audio, so
  it returns **80** mixed-format "parts" with scrambled `partNumber`. Also the
  search-result tap never probes the item at all (it plays the bare
  identifier as one stream), so the book is never detected. Filtering to a
  single best format yields exactly 20 chapters
  `laws_01…laws_20` (sortable by name).

## Items

### 1. Blank channel label until new content shows
`iPodView` header text is `currentPlaylist?.name ?? displayChannel.name`,
and `displayChannel = currentChannel ?? pendingChannel`. Playing a search
result sets `currentChannel = nil`, so it falls back to the **stale**
`pendingChannel` name.
**Fix:** header = `playerVM.currentPlaylist?.name ?? playerVM.currentChannel?.name ?? ""`.
`displayChannel` still drives the artwork color/icon (cosmetic) but never the
label. Search-result playback → blank label (track title shows below).

### 2. Edit / reorder / delete playlists
Add an `EditButton` to the **Playlists** section in `MainMenuView` with
`.onDelete` (skip Favorites) and `.onMove`. Persist order:
- `DatabaseService`: `ALTER TABLE playlists ADD COLUMN sort_order INTEGER`;
  `colPlaylistOrder`; order by `isFavorites DESC, sort_order ASC,
  createdAt ASC`; new `setPlaylistOrder([id])`.
- `PlaylistViewModel`: `reorderPlaylists(_:)`; `deletePlaylist` already exists
  (no-ops Favorites).
Favorites stays pinned (isFavorites DESC); only non-Favorites reorder.

### 3. Search history (Apple-native)
- `SearchViewModel`: `@Published recentSearches: [String]` persisted in
  UserDefaults (`searchHistory`, max 12, de-duped, most-recent first).
  Record the trimmed query on a successful `performSearch(page:0)`.
  `clearHistory()`; `removeHistory(_:)`.
- `SearchView`: when `query` is empty, render a `List` "Recent Searches"
  section — each row a `Button` that sets the query (triggers search) — with
  swipe-to-delete and a "Clear" trailing button. Native list styling.

### 4. Search result → action popup (no instant play)
Replace the row `onTapGesture { playSearchResult }` and the `+` button with a
single `confirmationDialog` (Apple-native) bound to a selected result:
- **Play** → `playerVM.playSearchResult(group)` + `dismissAll`.
- **Add to Playlist** → `AddToPlaylistSheet(track: searchTrack(group))`.
- **Add Entire Book/Album to Playlist** — only when the probed kind is
  `.book`/`.album` → `AddItemToPlaylistSheet(track: itemTrack(group))`
  (`resolveItemParts` probes `fetchTracksForIdentifier(group.id)`).
Dialog title shows the result title; both the row tap and the `+` open it.

### 5. Track-info section; remove "Play Entire"
In `iPodView.combinedTrackSheet`, the actions section becomes:
- **Add to Playlist** (the current single-track action), and
- if `currentTrackIsMultiPart`: **Add \(Book|Album) to Playlist**
  (`AddItemToPlaylistSheet`).
Delete the **Play Entire …** button entirely, and with it the now-unused
override-queue machinery:
- `PlayerViewModel`: remove `playEntireItem`, `overrideQueueTitle`,
  `prettifiedItemTitle`, `prettify`, the `advanceToNext` title-clear, and the
  `load(channel:)` override-queue resets.
- `QueueManager`: remove `overrideQueue`, `enqueueItemTracks`,
  `hasOverrideQueue`, `clearOverrideQueue`, the `_next` override branch and
  the `nextPart` `hasOverrideQueue` guard.
- `iPodView`: remove the screen-panel "Next: …" indicator.
Keep: `currentTrackIsMultiPart`, `probeCurrentTrack`, `resolveItemParts`,
`addEntireItemToPlaylist`, DB multi-part columns/methods, `AddItemToPlaylistSheet`.

### 6. Book / Album / Track marker + icon in search
- `SearchViewModel.ItemKind { track, album, book }`; `@Published itemKinds:
  [String: ItemKind]`. `loadKind(_:)` lazily fetches `archive.org/metadata/{id}`
  once (reuse the duration fetch — combine into one `loadItemInfo` that sets
  both duration and kind), classifying:
  - audio-file count ≤ 1 → `.track`
  - multi-file & collection contains `librivox`/`audio_bookspoetry` → `.book`
  - else multi-file → `.album`
- `SearchView` row: leading SF icon — `music.note` (track),
  `square.stack.fill` (album), `book.fill` (book) — plus a small caption
  label ("Track"/"Album"/"Book") next to the collection chip.

### 7 + 8a. Single-format, correctly-ordered multi-file extraction
Rewrite the audio-file selection in
`InternetArchiveService.fetchTracksForIdentifier`:
1. Group candidate files by a normalized format key; choose the **single**
   best present in priority `VBR MP3 → 128Kbps MP3 → 64Kbps MP3 → MP3 →
   Ogg Vorbis`, else by extension priority `mp3 → m4a → aac → opus → ogg →
   flac → wav`.
2. Keep only files of that one format.
3. **Sort by filename with localized numeric order** so `laws_01 < laws_02 <
   … < laws_10 < … < laws_20` (and chapter 2 < chapter 10). `partNumber` =
   sorted index (1-based) when count > 1.
4. Parse `length` via `parseRuntime` (handles `MM:SS`/`H:MM:SS`, not just
   seconds) so chapter durations are correct.
Result: `Laws_Plato` → 20 ordered MP3 chapters; `addEntireItemToPlaylist`
adds them in book order (8a). `resolveItemParts` already sorts by
`partNumber`, which is now meaningful.

### 9. Broaden the search query
`InternetArchiveService.search(query:page:)`:
`let q = "(\(query)) AND mediatype:audio"` (general default-field, matches the
IA website). Pagination/sort unchanged.

## Tests

- **SearchViewModel**: history record/dedupe/cap/clear/remove; `showNoResults`
  unaffected; `ItemKind` classification (track/album/book) from a count+collection
  helper; combined item-info caching.
- **InternetArchiveService (mock)**: `search` builds the general
  `(Q) AND mediatype:audio` query (capture URL, assert `q`);
  `fetchTracksForIdentifier` picks ONE format from a mixed MP3/OGG/FLAC/WAV
  fixture, returns count == chapter count, `partNumber` 1..n in natural name
  order; single-file item still has nil part info.
- **DatabaseService**: playlist `sort_order` round-trips; `setPlaylistOrder`
  reorders; Favorites stays first.
- **PlaylistViewModel**: `reorderPlaylists` persists; `addTracks` order
  preserved (8a).
- **PlayerViewModel**: removal of `playEntireItem`/override queue — delete the
  now-obsolete override-queue tests; keep/extend `addEntireItemToPlaylist`
  (asserts parts added in `partNumber` order); `load(channel:)` no longer
  references override queue.
- **QueueManager**: delete override-queue tests; keep existing
  `nextPart`/leak/shuffle tests (re-verify the `nextPart` guard removal).
- **Integration (live IA)**: `search("tarrega guitar")` returns ≥ 10 and
  includes a Yepes/Tárrega item (regression for item 9);
  `fetchTracksForIdentifier("Laws_Plato")` returns ~20 single-format chapters
  with strictly increasing `partNumber` and names in order (items 7/8a);
  end-to-end `addEntireItemToPlaylist` from a `Laws_Plato` search result adds
  all chapters in order.

## Sequence

Plan (this file) → 9 → 7/8a → 5 (remove Play Entire) → 1 → 6 → 4 → 3 → 2 →
tests → `swiftc -parse` all changed files → curl-verify queries → single
commit → push → monitor CI (Unit + Integration + TestFlight) to green.
