# Revisions — May 22

Plan for the requested fixes. Implementation follows.

## 1. Per-track download progress on the playlist screen
Today "Download All" reports progress only by playlist id, so individual
rows show nothing. Add byte-level progress:
- `DownloadManager.download(track:onProgress:)` using a
  `URLSessionDownloadDelegate` (`didWriteData`) to report
  `totalBytesWritten / totalBytesExpectedToWrite`.
- `OfflineDownloadService` gains `@Published var trackProgress: [String:Double]`
  updated per track during BOTH single-track and playlist jobs; cleared on
  completion (the row then reads `localFilePath != nil`).
- `PlaylistDetailView.trackDownloadControl`: not downloaded → grey down-arrow;
  downloading → blue determinate `ProgressView(value:)` (circular) with %;
  downloaded → solid blue check.

## 2. Combined play/pause wheel button (never changes)
Replace the toggling `play.fill`/`pause.fill` glyph at the wheel bottom with
a fixed `playpause.fill`.

## 3. Recently Played always shown
Render the Recently Played section even when empty (placeholder
"Nothing played yet"); don't drop the category after Clear All.

## 4. Recently Played updates for every track
`recordPlayed` is only hit on channel auto-advance / News. Record in the
single playback funnel `playTrack` for every real (non-ambient) track so
playlists, search picks, first-of-channel, etc. all show up. Context id =
channel id / playlist key / "direct".

## 5. Categories hide on search FOCUS (not first keystroke)
Switch the menu/results decision to `@Environment(\.isSearching)` (true the
moment the search field is focused) by reading it in a child of the
`.searchable` container.

## 6. Search only on submit
Stop searching on `onChange`. Trigger `searchVM` from `.onSubmit(of:.search)`
(Return / Search key). Clearing the field restores the menu.

## 7a. Search noise ("plato laws" → Alan Watt)
Keyword-stuffed talk-radio items match via their huge subject lists. Switch
`buildSearchQuery` to an ANCHORED form: every token must match
title/creator/subject (AND'd) AND at least one token must hit title or
creator. Curl-verified: "plato laws" drops Alan Watt from ~8/16 to ~1/7;
"tarrega guitar" keeps Yepes-Tárrega / Recuerdos / Li Jie (12 results).

## 7b. Category icons in the menu
Each collapsible category header gets a leading SF Symbol
(Curated/Ambient/News/Contemporary/Audiobooks/Lectures).

## 8. Playlist Shuffle starts at a random track
New `PlayerViewModel.shufflePlaylist(_:)` — shuffleMode on, pick a random
start index, play it; subsequent advances already pick randomly.

## 9. "Add to Favorites" in Track Info
Add a toggle/button to the Track Info sheet that adds/removes the current
track from the Favorites playlist (favorites was removed from the track box).

## 10. Playlist screen title
NavigationTitle = "Playlist"; the playlist's name shown as a large row
immediately beneath, for legibility.

## 11. Playlist screen add-tracks affordance
Remove the toolbar "+"; add an "Add to Playlist…" row that opens AddTracksView.

## 12. Menu-button navigation redesign
- Remove the "tap top of track box" target entirely.
- Wheel MENU single-tap: playlist → Playlist screen, channel → Channel Info,
  nothing playing → Main Menu.
- Wheel MENU double-tap: straight to Main Menu.
- Implementation: MainMenuView hosts a NavigationStack with a `path`;
  PlaylistDetailView and ChannelInfoView become pushed destinations, so the
  standard nav back-chevron returns to the Main Menu list (the requested
  "back" button). iPodView presents MainMenuView with an optional initial
  route; the separate channel-info / active-playlist sheets are removed.

## 13. This document, then implementation.

## Validation
swiftc -parse all changed files; curl-verify search shapes (done); update
tests (search query/anchored, recently-played coverage); push + iterate CI.
