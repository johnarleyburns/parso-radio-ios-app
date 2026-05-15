# Improvements Plan

## Group A — UI Polish

**A1. Click wheel: restore flat metallic look**
- `ClickWheel` outer ring: revert to `Color(.secondarySystemGroupedBackground)` with sharp card shadow (drop the charcoal fill).
- Keep center button as `Color(.systemBackground)`.
- Cardinal icons: use `.primary` (dark on light background), not white.

**A2. Screen panel margins: equal horizontal, reduce top**
- `iPodView` screen panel: use symmetric horizontal padding (currently left≠right due to GeometryReader frame).  
  Fix: `padding(.horizontal, 12)` applies equally — the unequal right margin comes from the `info.circle` button overlay. Move info button inside the ZStack content (not outside it as an overlay) so it doesn't affect the clipped bounds.
- Reduce top padding from `8` to match the horizontal `12` gutter: `padding(.top, 12)`.

**A3. Wheel equidistant spacing**
- Replace the current `Spacer(minLength: 8) / Spacer(minLength: 12)` approach with an explicit centered layout so the wheel sits with equal gaps: bottom of screen panel → wheel top, wheel bottom → bottom safe-area edge, left/right edges.
- Use `VStack` with `.frame(maxWidth: .infinity, maxHeight: .infinity)` and place the wheel in a centered `Spacer`-balanced layout. Target: wheel diameter = `min(geo.size.width - 48, (geo.size.height * 0.50) - 32)`.

---

## Group B — Functional Fixes

**B1. Playlist duplicate prevention on folder import**
- `LocalFileImportService.importFolder`: before copying and creating a track, fetch existing tracks for the playlist from the DB and build a `Set<String>` of `title.lowercased() + "|" + artist.lowercased()`.
- Skip any file whose extracted `(title, artist)` pair already appears in that set.
- Same guard in `importFile` for single-file imports.
- `DatabaseService.addTrack` already uses `insert(or: .ignore)` on `UNIQUE(playlist_id, track_id)` as a second safety layer — but the UUID-per-import means it never fires; the service-level check is the real guard.

**B2. Remove "Download Channel" everywhere**
- `MainMenuView`: remove the `Download \(displayChannel.name)` row.
- `iPodView.moreOptionsSheet`: remove the "Download Channel" button from the Track section.
- `iPodView.contextMenu` (long-press on screen panel): remove "Download Channel".
- `MainMenuView` init: remove `onDownloadChannel` parameter. Update all call-sites in `iPodView`.

**B3. Remove info (i) button from screen panel**
- `iPodView.screenPanel` top-right `Button { showAbout = true }`: delete it. About is already in the ••• sheet.

**B4. Playlist → play → dismiss sheet stack**
- `PlaylistDetailView`: after `Task { await playerVM.loadPlaylist(playlist, startingAt: track) }`, call the environment dismiss **twice** — once to close `PlaylistDetailView` and once to close the parent `PlaylistListView` sheet.
- Approach: pass a `dismissAll: () -> Void` closure from `iPodView` into `PlaylistListView` → `PlaylistDetailView`. When a track is tapped, call `playerVM.loadPlaylist(...)` then `dismissAll()`.

**B5. Playlist reorder in Edit mode (persistent)**
- `PlaylistDetailView` already has an Edit button; add `.onMove` to the `ForEach` so rows can be dragged.
- On move: call `playlistVM.reorderTracks(_:inPlaylist:)` which calls `db.setTrackOrder(_:inPlaylist:)` — this already exists in both `PlaylistViewModel` and `DatabaseService`. Just wire `.onMove` to call it.

**B6. Playlist name shown in track screen panel**
- `PlayerViewModel`: when loading a playlist (`loadPlaylist`), set `channelDescription = playlist.name` (currently it sets it but `currentChannel` becomes nil, so `displayChannel.name` shows the last channel, not the playlist).
- `iPodView.screenPanel` top-left: show `playerVM.currentPlaylist?.name ?? displayChannel.name` as the primary label when a playlist is active.
- Expose `currentPlaylist` (already `var` on `PlayerViewModel`) via a `@Published` wrapper or keep as-is and read it directly.

**B7. Star → Heart icon for favorites**
- `iPodView.scrubberRow`: change `"star.fill"` / `"star"` → `"heart.fill"` / `"heart"`.
- Color: `isFavorite ? .red : .white.opacity(0.7)` (red heart when favorited).

**B8. Back button stays within current channel/playlist**
- `PlayerViewModel.playPreviousTrack`: currently pops `playHistory` which may contain tracks from previous channels.
- Fix: clear `playHistory` in `load(channel:)` and `loadPlaylist(_:startingAt:)` when a new source is loaded, so back can never cross channel/playlist boundaries.

**B9. Forward button: skip to next track**
- `ClickWheel.onForward` calls `playerVM.skip()`, which calls `audioPlayer.skip()` then `Task { await advanceToNext() }`.
- The issue: `audioPlayer.skip()` stops AVPlayer but `advanceToNext()` is called asynchronously in a `Task`. Confirm this resolves correctly; if `audioPlayer.skip()` emits `onTrackFinished` before `advanceToNext()` runs from the explicit call, there's a race. 
- Fix: in `PlayerViewModel.skip()`, guard against double-advance: set a `isSkipping` flag; in `onTrackFinished`, return early if `isSkipping`.

---

## Group C — Channel/Navigation Changes

**C1. Remove "Recently Played" section from ChannelSelectorView**
- `ChannelSelectorView`: remove the `Section("Recently Played")` block and the `recentChannels` computed var that reads `UserDefaults.visitedChannelIds`.
- Keep `visitedChannelIds` writes in `PlayerViewModel.load` (used for other purposes); just stop displaying the section.

**C2. Add "Curated" category — positioned before Ambient, after Favorites in selector**
- `ChannelSelectorView`: add `"Curated"` to the ordered category list, between `"Favorites"` (if shown) and `"Ambient"`.
- `Channel.swift`: add new curated channels with `category: "Curated"` — starting with Spanish Guitar (see Group D).

**C3. Rename "Select Channel" → "Channels" in main menu**
- `MainMenuView` row label: `"Select Channel"` → `"Channels"`.

---

## Group D — Spanish Guitar Curated Channel

### D1. Research findings (curl-verified 2026-05-14)

| Query | numFound |
|---|---|
| `subject:"spanish guitar"` | 40 |
| `subject:"flamenco"` | 1,871 |
| `subject:"classical guitar" OR subject:"spanish guitar" OR subject:"flamenco"` | 2,103 |
| Composer creators (Tárrega, Segovia, Barrios, Albeniz, Granados, Rodrigo, de Falla, Llobet, Pujol) + `subject:guitar` | 11 |

**Top 20 Spanish guitar composers/performers for IA search:**
1. Francisco Tárrega
2. Andrés Segovia (performer)
3. Agustín Barrios Mangoré
4. Isaac Albéniz
5. Enrique Granados
6. Joaquín Rodrigo
7. Manuel de Falla
8. Miguel Llobet
9. Emilio Pujol
10. Fernando Sor
11. Mauro Giuliani
12. Ferdinando Carulli
13. Matteo Carcassi
14. Leo Brouwer
15. Gaspar Sanz
16. Luís de Milán
17. Luys de Narváez
18. Heitor Villa-Lobos
19. Joaquín Turina
20. Federico Moreno-Torroba

### D2. Search strategy

The most productive IA query combines subject tags (high recall) with explicit exclusions:

```
mediatype:audio AND (
  subject:"spanish guitar" OR subject:"classical guitar" OR
  subject:"flamenco" OR subject:"guitarra" OR subject:"fingerstyle"
) NOT subject:rock NOT subject:electronic NOT subject:experimental
  NOT subject:"electric guitar"
```

License filtering: in `LicenseValidator` as always — no licenseurl wildcards in the Solr query.

### D3. Implementation

- Add `id: "spanish-guitar"` channel to `Channel.swift` under `category: "Curated"`:
  ```swift
  Channel(
    id: "spanish-guitar", name: "Spanish Guitar", category: "Curated",
    icon: "guitars",
    tags: ["spanish guitar", "classical guitar", "flamenco", "guitarra", "fingerstyle guitar"],
    excludeTags: ["rock", "electronic", "experimental", "electric guitar"],
    ...
  )
  ```
- Add `excludeTags: [String]` to `Channel` model (default `[]`).
- `InternetArchiveService.fetchTracks(tags:)`: append `NOT subject:"\(tag)"` for each `channel.excludeTags`.
- Shuffle is already the default for tag-based channels via `QueueManager`.

---

## Group E — Branding

**E1. Rename "Parso Radio" → "Parso Music" in all user-visible strings**
- `SplashView.swift` line 27: `Text("Parso Radio")` → `Text("Parso Music")`
- `AboutView.swift`:
  - Line 51: `Text("Parso Radio")` → `Text("Parso Music")`
  - Line 88 privacy policy body: `"Parso Radio (the \"App\")"` → `"Parso Music (the \"App\")"`
  - Line 113 children's privacy: `"Parso Radio is"` → `"Parso Music is"`
  - Line 128 footer: `"Parso Radio streams"` → `"Parso Music streams"`

---

## Implementation Sequence

1. Group E (branding — trivial find/replace, low risk)
2. Group C (channel changes — data-only, no logic)
3. Group A (UI layout — visual only)
4. Group B1 (duplicate prevention — most user-visible bug)
5. Group B2–B9 (remaining functional fixes)
6. Group D (Spanish Guitar channel — curl-verify query, then add channel + excludeTags)
7. Push, monitor CI
