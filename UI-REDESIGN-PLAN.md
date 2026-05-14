# UI Redesign + Bug Fix Plan

## Group A — Bug Fixes

**A1. Blank track display on launch**
- `PlayerViewModel.playTrack`: pre-set `trackDuration = track.duration > 0 ? track.duration : nil` before resolving the URL so the scrubber shows something while AVPlayer buffers.

**A2. Right-side shows total duration instead of remaining**
- `iPodView` scrubber row: change `Text(formatTime(dur))` → `Text("-\(formatTime(max(0, dur - playerVM.currentPosition)))")`.

**A3. Remove non-functional book-skip buttons**
- Remove `backward.end.fill` and `forward.end.fill` buttons from the controls row beneath the click wheel (they do nothing for non-librivox channels and confuse users).

**A4. Favorites heart silently does nothing**
- `iPodView.task`: add `await playlistVM.loadPlaylists()` before `playerVM.load(...)` so `favoritesPlaylist` is populated for returning users who never trigger the TOS-change observer.

**A5. Import folder crashes the app**
- `DocumentPickerView`: add `asCopy: Bool = true` parameter, thread it through `UIDocumentPickerViewController(forOpeningContentTypes:asCopy:)`.
- `AddTracksView` folder picker call-site: pass `asCopy: false` so the OS grants a security-scoped URL that `LocalFileImportService.importFolder` can access via `startAccessingSecurityScopedResource()`.

---

## Group B — Search (Internet Archive + LibriVox)

FMA is NOT supported (no public API without a key) and is being removed from search entirely.

**B1. Implement `InternetArchiveService.search(query:page:)`**
- Query: `(title:(Q) OR creator:(Q)) AND mediatype:audio`
- 20 rows per page, sorted `addeddate desc`; `start = page * 20`
- Curl-verified: `numFound: 4834` for "beethoven"
- Returns `[SearchViewModel.ResultGroup]`, one group per IA identifier

**B2. Implement `InternetArchiveService.searchLibrivox(query:page:)`**
- Same as B1 with `AND collection:librivoxaudio`
- Curl-verified: `numFound: 26` for "sherlock"

**B3. Implement `InternetArchiveService.fetchTracksForIdentifier(_:)`**
- Hits `archive.org/metadata/{id}`, extracts audio files (VBR MP3 → 128Kbps MP3 → 64Kbps MP3 → MP3 → any audio extension)
- Returns `[Track]` with duration from file `length` field

**B4. Remove FMA from search**
- `SearchViewModel.SearchSource`: drop `case fma`; drop `fmaService` property and init param
- `SearchViewModel.expandGroup`: drop `.fma` case
- `SearchViewModel.performSearch`: drop `.fma` case
- `SearchView.init`: drop `fmaService` parameter
- `AddTracksView`: update label "Search (IA / Librivox)" (FMA removed)

**B5. Tests**
- Unit tests (MockURLProtocol) in `InternetArchiveServiceTests.swift`:
  - `testSearchReturnsResultGroups`
  - `testSearchLibrivoxFiltersToLibrivoxCollection`
  - `testFetchTracksForIdentifierReturnsAudioFiles`
  - `testSearchPaginationStartParam`
- Integration tests in `InternetArchiveIntegrationTests.swift`:
  - `testSearchBeethovenReturnsResults` (general search)
  - `testSearchLibrivoxSherlockReturnsResults` (librivox search)
  - `testFetchTracksForIdentifierReturnsPlayableURL`

---

## Group C — UI Redesign (iPod Classic)

**C1. iPod Classic device layout**
- Device body: `Color(red: 0.29, green: 0.33, blue: 0.41)` (#4A5568), corner radius 32pt, fills safe area
- Screen panel (top ~50%): full-bleed album art + dark gradient overlay; corner radius 20pt
- Click wheel panel (bottom ~50%): charcoal `Color(red: 0.10, green: 0.10, blue: 0.11)` (#1A1A1B), wheel 85% of device width

**C2. Screen panel content**
- Album art: full-bleed, scaledToFill, clipped to panel
- Gradient: `LinearGradient([.clear, .black.opacity(0.75)], top → bottom)` over art
- Metadata stack (center-right alignment):
  - Channel name: caption, secondary, top-left area
  - Track title: bold 17pt, right-aligned
  - Artist: 14pt regular, 0.8 opacity
  - License badge row
  - Part N of M: caption ("Part 2 of 18") when `partNumber != nil && (totalParts ?? 0) > 1`
- Star (favorites) icon: leading, bottom of panel, above scrubber
- Scrubber row at panel bottom: `Text(elapsed)` — `Slider` — `Text("-remaining")`
- ••• (ellipsis.circle) button: trailing, opens more-options sheet

**C3. Dominant color scrubber tinting**
- `@State private var scrubberTint: Color = .accentColor`
- On artwork change: `scrubberTint = Color(ArtworkService.shared.dominantColor(from: art))` (fallback to `.accentColor` when no art)
- Slider uses `.tint(scrubberTint)`

**C4. More-options sheet (•••)**
- Sheet contains: shuffle toggle, repeat toggle, "Add to Playlist", "Download Channel", "Track Details"
- Shuffle/repeat move out of the separate row (which is removed)

**C5. Click wheel styling**
- Outer ring: matte charcoal with inner shadows for depth
- Cardinal button icons in `.primary` (white on charcoal background)
- Center button: slightly lighter charcoal, 30% of wheel diameter
- Gesture: unchanged (SpatialTapGesture, quadrant-based routing)

---

## Sequence

1. Write this plan to `UI-REDESIGN-PLAN.md` ✓
2. Implement Group A (bug fixes)
3. Implement Group B (search + FMA removal + tests)
4. Implement Group C (full UI redesign)
5. Curl-verify all API queries (done before writing code)
6. Push and monitor CI
