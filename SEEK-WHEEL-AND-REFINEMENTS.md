# Seek Wheel & Refinements — consolidated implementation plan

Single batch. No local Swift compiler — every file `swiftc -parse`'d; every IA
query curl-verified before commit; CI driven to green.

## 1. Three new pure-Lucene Curated channels

`ParsoRadio/Resources/ia_queries.json` (+`Channel.swift` Curated section,
`ChannelTests` counts). Reuses the registry path entirely (routing,
`sort=random`, stamp isolation, parametrized integration test auto-cover).

| id | iaQuery | curl numFound |
|---|---|---|
| `netlabels` | `collection:netlabels AND mediatype:audio` | 78,120 |
| `lofi` | `collection:netlabels AND mediatype:audio AND (subject:lofi OR subject:"lo-fi" OR subject:"lo fi" OR subject:lo_fi)` | 2,233 |
| `rpm-78` | `collection:78rpm AND mediatype:audio` | 309,347 |

matchTags `[id]`. ChannelTests: total 68→71, Curated 7→10, id set +3.

## 2. Upload / recording date

- `Track`: add `recordingDate: Date?`; computed `bestDate`/`dateLabel`
  (`recordingDate` → "Recorded", else `addedDate`/`displayDate` → "Added").
- `InternetArchiveService.fetchTracks(iaQuery:)`: `fl[]=date` (+`year`),
  parse into `recordingDate` (upload `addeddate` stays the fallback). No
  filtering — still pure Lucene.
- `TrackDetailView`: a date row in the Track section (hidden if no date).
- News (`preferredSource == "podcast"`): show the episode date as a caption
  line in `iPodView.trackMetadataStack` (pubDate already in `addedDate`).
- Decision (single-track app, no episode-list screen): the news "track
  listing" surface = the on-screen now-playing metadata. No new list view.

## 3. Track-panel polish + combined Info/Options sheet

`iPodView.swift`:
- Remove the channel-description subtitle `Text` (keep only name/playlist).
- `cleaned(_:)` helper → treats ""/"unknown" (case-insensitive) as nil;
  artist/composer/etc. rows hidden when nil (no literal "Unknown").
- Add a short top dark gradient scrim behind the channel title.
- Merge `TrackDetailView` rows + `moreOptionsSheet` into ONE sheet
  (`trackSheet`, driven by `showMoreOptions`). Both the ••• button and the
  screen-panel tap open it. Remove the standalone `showTrackDetail` sheet,
  the "Track Details" menu button, and the context-menu "Track Details".

## 4. iPod-style seek wheel

New: `ParsoRadio/Views/SeekWheelMath.swift` (4 pure fns),
`ParsoRadio/Views/SeekWheelViewModel.swift` (`@MainActor ObservableObject`),
`ParsoRadio/Core/Services/Playback/SeekHapticsController.swift` (CoreHaptics,
simulator-safe no-op). `ClickWheel` gains `currentTime/duration/onSeek/
onScrubChanged`, a `.simultaneousGesture(DragGesture(minimumDistance:12))`
(coexists with the transport `SpatialTapGesture`), and an accent progress
arc + 16pt thumb on the existing ring (no center time label). Seek only when
`duration > 0`; sets `isScrubbing` during drag; `seek` throttled ~0.15 s.
Tests: `SeekWheelMathTests`, `SeekWheelViewModelTests` (pure, in ParsoMusicTests).

## 5. Search always-IA + duration tag + tap-to-play + smooth transitions

- `SearchView`/`SearchViewModel`: remove the source `Picker`; always
  `archiveService.search`; drop `SearchSource`/`source`/`expandGroup`/
  `isExpanded`/`trackCount`; remove chevron + "N tracks"; add a duration
  tag; tapping a result plays it and dismisses to the main screen.
- `InternetArchiveService.searchGroups`: `fl[]=runtime` (fallback `length`)
  → `ResultGroup.duration` (curl-verified at implement; hidden if absent).
- `PlayerViewModel.playSearchResult(_:)`: ad-hoc single item; inject
  `playerVM` + `dismissAll` into the Search sheet (PlaylistList pattern).
- Shared `beginTransition(pre:)` called synchronously at the top of `load`,
  `loadPlaylist`, `playSearchResult` BEFORE any await: clear currentTrack/
  position/duration/artwork/error, pre-populate `currentTrack` with the
  known upcoming track, `isLoading=true` (existing spinner). `playTrack`
  finalizes metadata + starts audio in one state update.
- Tests: SearchViewModel always-IA + duration parse; PlayerViewModel
  `beginTransition` invariants (locks "no stale artifacts").

## Constraints
iOS 17 target. No third-party deps. `swiftc -parse` every file; curl-verify
every query; line-read changed files; CI (unit + live integration) green.
