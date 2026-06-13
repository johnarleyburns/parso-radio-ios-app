# PHASE 8 (standalone) — Fix the broken player, then finish draining the ViewModel

_This document is self-contained. It does not depend on any earlier plan. Read §0 (rules) and §1 (context) first, then do the tasks in order. **Task 1 is an urgent user-facing regression — do it first and ship it before anything else.**_

---

## 0. Rules (apply to every task)

- **One task per commit; the app must build and the full unit suite must pass before moving on.** Commit prefix `rearch(phase8):`.
- **After adding/removing/renaming any `.swift` file, run `xcodegen generate`** — files are not auto-discovered, and a deleted file leaves dangling project references until you regenerate. Then:
  ```bash
  xcodegen generate
  xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:ParsoMusicTests
  ```
- **Invariants that must not break** (these were hard-won bug fixes):
  - `currentChannel` and `currentTrack` on `PlayerViewModel` are `@Published`. Do not change that.
  - `playbackContextToken` aborts stale `playTrack` calls during rapid skip/channel-switch; preserve its checks when moving advance/playlist code.
  - `currentPosition` is throttled to ~2×/sec; keep the throttle.
  - The stall watchdog disarms only on `seconds > 0`; zero ticks must not reset it.
  - Curation is DB-as-source-of-truth: never write verdicts to JSON, never add a JSON/bundled fallback to `LiveCurationStore.pool(for:)`.
  - `Track` init order: `partNumber` before `parentIdentifier`. `Channel` init order: `category` before `icon`, `preferredSource` before `feedURL`.
- **Move, don't copy.** When relocating logic into a controller, delete the original body; leave at most a one-line forwarder, and only if something still calls the ViewModel method.

## 1. Context (what you're working in)

iOS app, SwiftUI + MVVM, XcodeGen project (`ParsoMusic.xcodeproj` generated from `project.yml`), iOS 17+. Audio playback is driven by `PlayerViewModel` (an `@MainActor ObservableObject`). Content type is modeled by `Channel.mediaKind` (`.music`, `.audiobook`, `.podcast`, `.lecture`, `.ambient`) and a derived `Channel.behavior` (`PlaybackBehavior`) value type with capability flags (`allowsShuffleToggle`, `showsScrubbableProgress`, `supportsSpeedControl`, `supportsSleepTimer`, `supportsChapters`, `supportsBookmarks`, `supportsBookSkip`, etc.). Per-type playback logic is being moved out of `PlayerViewModel` into focused controllers under `ParsoRadio/Core/Services/Playback/` (existing: `SleepTimerController`, `BookmarkController`, `RecentlyPlayedController`, `SessionRestoreController`, `RecommendationsController`, `AuditionController`, `WholeItemController`). The player UI is `ParsoRadio/Views/Player/NowPlayingSheet.swift`, composed from small control views in the same folder (`TransportControls`, `ScrubBar`, `ShuffleToggle`, `SpeedControl`, `SleepTimerControl`, `ChapterButton`, `BookmarkButton`, `BookSkipControls`).

**Controller pattern to follow** (see `SleepTimerController` as the reference): `@MainActor` class, holds an `unowned`/`weak` back-reference to the VM, implements the logic, and mutates the VM's existing `@Published` properties through that reference. **Keep the `@Published` properties on `PlayerViewModel`** so no view's bindings change. Register each controller as a `lazy var` on the VM beside the existing ones.

---

## TASK 1 — URGENT: the Now Playing screen is collapsed to name + author only

### Symptom
On the main player, **only the track title and artist render** — no play/pause, skip, shuffle, repeat, speed, sleep, chapters, favorites, share, AirPlay, archive.org link, or artwork.

### Root cause
In `ParsoRadio/Views/Player/NowPlayingSheet.swift`, both the `artwork` view (line ~45) and the `behaviorComposedControls(...)` block (gated at line ~16) are wrapped in `if let channel = playerVM.currentChannel`. `trackInfo` (name/author) is the only block gated on `currentTrack` instead. `PlayerViewModel.load()` sets `currentChannel = nil` whenever it enters playlist / album / whole-item playback (assignments around lines 1421, 1434, 1455, 1482, 1729, 1763) and `currentChannel` is also nil in the brief window before a load resolves. **Any nil moment collapses the whole player to name + author.** The transport buttons (play/pause/prev/next/shuffle/repeat) already exist inside `TransportControls.swift` — they're simply hidden by this gate.

### Additionally missing (never ported into the sheet — must be added)
Favorites, Share, AirPlay, "View on archive.org", and real album artwork. The reusable pieces already exist in the codebase:
- **AirPlay**: `ParsoRadio/Views/AirPlayButton.swift` (`AirPlayButton()`, an `AVRoutePickerView` wrapper).
- **Share**: `ShareURLBuilder.url(for: track) -> URL?` in `ParsoRadio/Core/Services/ShareURLBuilder.swift`; use SwiftUI `ShareLink` (see usage in `ChannelInfoView.swift`).
- **Artwork**: `playerVM.currentArtwork` is a `@Published UIImage?` already populated during playback — display it; the sheet currently ignores it and shows only a channel-icon glyph.
- **Favorites**: a `FavoritesStore` is already injected into the sheet from `ListenView`'s `fullScreenCover` (`.environmentObject(favorites)`), but `NowPlayingSheet` doesn't declare or use it. Read `FavoritesStore`'s API and add a heart toggle (favoriting an audiobook should target the book/work, music a track — match the store's existing kinds).
- **archive.org link**: build from the track's identifier; see the existing pattern in `NowPlayingAlbumDetailView.swift`.

### Fix

1. **Decouple the player from `currentChannel`.** Render the player whenever there is a track (or while loading), deriving behavior defensively:
   ```swift
   // Behavior drives only the type-specific accessory controls.
   // Fall back to music-style behavior when there is no single channel
   // (e.g. playlist/album mode) so the core player still renders fully.
   private var behavior: PlaybackBehavior {
       playerVM.currentChannel?.behavior ?? MediaKind.music.behavior
   }
   ```
   Restructure `body` so that **artwork, transport, and the global controls (favorites/share/AirPlay) render based on `currentTrack`/loading state — never gated on `currentChannel`.** Only the *type-specific* accessories (scrub, speed, sleep, chapters, book-skip, bookmark) are gated on the `behavior` flags above.

2. **Show real artwork.** In the `artwork` view, prefer `playerVM.currentArtwork`:
   ```swift
   if let img = playerVM.currentArtwork {
       Image(uiImage: img).resizable().scaledToFill()
           .frame(width: 260, height: 260)
           .clipShape(RoundedRectangle(cornerRadius: 28))
           .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
   } else {
       // existing gradient + channel.icon fallback, but use a NEUTRAL
       // gradient/icon when currentChannel is nil so it still renders.
   }
   ```
   The loading spinner overlay (`isLoading && currentTrack == nil`) stays.

3. **Add the missing global controls** to the player (visible whenever `currentTrack != nil`, independent of channel):
   - Favorites heart (`@EnvironmentObject var favorites: FavoritesStore` + toggle).
   - `ShareLink(item: ShareURLBuilder.url(for: track) ?? <fallback>)` — guard the optional.
   - `AirPlayButton()`.
   - A "View on archive.org" link for tracks whose source is Internet Archive (reuse `NowPlayingAlbumDetailView`'s URL pattern; hide it for non-IA sources).

4. **Reconcile the shuffle/repeat duplication and make them behavior-correct.** `TransportControls.swift` currently hardcodes a shuffle button and a repeat button into the transport row for *every* content type, while `behaviorComposedControls` *also* conditionally adds a separate `ShuffleToggle`. That's both duplicated and wrong for spoken-word (an audiobook should not offer shuffle/repeat). Fix:
   - `TransportControls` = previous / play-pause / next only (always shown).
   - Show shuffle and repeat **only when `behavior.allowsShuffleToggle`** (music + For-You), in the accessory row. Remove the hardcoded shuffle/repeat from `TransportControls` and remove the now-redundant separate `ShuffleToggle` if it duplicates this.

5. **Result per content type** (verify each — see gate): every type shows artwork + prev/play/next + favorites + share + AirPlay; **music** adds shuffle/repeat; **audiobook** adds scrub + speed + sleep + chapters + book-skip + bookmark (no shuffle); **podcast/lecture** adds scrub + speed + sleep + bookmark; **ambient** adds sleep only. **Playlist mode (channel nil)** shows the full core player (artwork + transport + favorites/share/AirPlay) and does not collapse.

### Verification gate
- Build + full unit suite green.
- **Manual smoke is the real gate here.** From the Listen tab, open one channel of each kind (`piano-hour` music, `lv-general-fiction` audiobook, `news-nprup-first` podcast, `oxford-philosophy` lecture, `ambient-rain` ambient) and confirm the correct full control set renders and every button works (play/pause, skip both directions, favorite toggles and persists, share sheet opens, AirPlay picker opens, archive.org link opens for IA tracks, scrub/speed/sleep/chapters where applicable). Then start a **playlist** and confirm the player still shows artwork + transport + favorites/share/AirPlay (channel is nil here) and never collapses to name-only.
- Dynamic Type (largest size), Dark Mode, Reduce Transparency, and VoiceOver labels correct on all controls.

### Acceptance
- The player renders its full, type-appropriate control set in every state, including playlist/album mode and during loading.
- No part of the player is gated on `currentChannel != nil`; only type-specific accessories are gated on `behavior`.
- Favorites, share, AirPlay, archive.org link, and real artwork are present.

---

## TASK 2 — De-duplicate ViewModel/controller methods

Some methods were copied into controllers but their originals still sit in `PlayerViewModel`. Make the **controller canonical** and delete the VM body (or leave a one-line forward only if callers reference the VM method).

1. `playEntireCurrentItem()` — exists in `WholeItemController` **and** `PlayerViewModel` (~1404). Delete the VM copy; route callers to the controller.
2. `playAlbumTracks(_:title:)` — body in VM (~1410). Move into `WholeItemController`; redirect callers.
3. `fetchCurrentItemChapters()` — exists in `BookmarkController` **and** `PlayerViewModel` (~1927). Delete the VM copy; route `ChapterButton`/`ChapterListView` to `playerVM.bookmarks.fetchCurrentItemChapters()`.

**Gate:** build + tests green; each method name is defined exactly once outside the VM. **Acceptance:** no duplicated bodies remain.

---

## TASK 3 — Extract `PlaylistPlaybackController`

New file `ParsoRadio/Core/Services/Playback/PlaylistPlaybackController.swift`. Move all playlist-playback logic out of the VM: `loadPlaylist(...)` (~1750), `shufflePlaylist(_:)` (~1793), `resumePlaylist(_:autoPlay:)` (~1800), `advancePlaylist()` (~994), plus `savedPlaylistResume` and `playlistKey`.

- Keep the playlist `@Published` state (`currentPlaylist`, playlist index/tracks, mode flag) **on the VM**; the controller reads/writes via the `vm` back-reference.
- `advanceToNext()` stays on the VM but delegates to `playlistPlayback.advancePlaylist()` when in playlist mode. **Preserve `playbackContextToken`** across the call boundary so stale advances still abort.
- Note: these paths set `currentChannel = nil` (legitimate — a cross-channel playlist has no single channel). Task 1 already made the UI robust to that, so leave the nil semantics intact.
- Wire `private(set) lazy var playlistPlayback = PlaylistPlaybackController(db: db, playerVM: self)` beside the existing controllers.

**Gate:** build + tests green; smoke — load a playlist, shuffle it, auto-advance across 2–3 tracks, background/resume mid-playlist; the player UI stays intact throughout. **Acceptance:** no playlist-playback bodies remain in the VM.

---

## TASK 4 — Fold book-navigation and autosave into existing controllers

Don't create one-method controllers (KISS) — place these where the domain already lives:

1. **Book navigation → `WholeItemController`**: move `skipToNextBook()` (~1811) and `skipToPreviousBook()` (~1818).
2. **Autosave → `SessionRestoreController`** (autosave *is* session persistence): move `saveAutosaveForCurrentTrack()` (~1938), `deleteAutosaveForTrack(...)`, and the `autosavePosition` logic.
3. **Variable speed → leave on the VM.** `setPlaybackRate(_:)` (~1830) is a one-liner against the audio engine and is transport-adjacent; do not extract it.

**Gate:** build + tests green (`AutosaveBookmarkTests` especially); smoke — speed persists across tracks, next/prev-book works on an audiobook, position restores on relaunch. **Acceptance:** book-nav and autosave bodies no longer in the VM.

---

## TASK 5 — Delete the last orphan and clean a stale comment

1. `ParsoRadio/Views/NowPlayingView.swift` (23 lines) has **0 external references** (superseded by `NowPlayingSheet`). Confirm, then `git rm` it. Do **not** touch `NowPlayingScreen` or `NowPlayingAlbumDetailView` — both are live.
   ```bash
   grep -rn "NowPlayingView(" ParsoRadio --include="*.swift" \
     | grep -v "Views/NowPlayingView.swift" | grep -v NowPlayingAlbum   # expect empty
   ```
2. `ParsoRadio/Core/Services/ShareURLBuilder.swift:9` has a doc comment referencing the deleted `iPodView`. Reword it (e.g. "Builds a share URL for a track; unit-tested in isolation.").
3. `xcodegen generate`.

**Gate:** clean build + tests green; no dangling references. **Acceptance:** no orphaned views; no comments cite deleted types.

---

## TASK 6 — Mini-player hides the bottom tab bar (can't navigate while playing)

### Problem
`ParsoRadio/Views/RootTabView.swift` applies the mini-player as `.safeAreaInset(edge: .bottom) { MiniPlayer() }` **on the `TabView` itself** (lines ~17–19). A bottom safe-area inset on a `TabView` is drawn at the screen's bottom edge, *over* the system tab bar — so once something is playing, the mini-player covers Listen/Library/Search and the user can't navigate.

### Fix
Move the mini-player dock from the `TabView` onto the **content of each tab**, so it floats *above* the tab bar (the Apple Music / Podcasts pattern) instead of replacing it.

```swift
struct RootTabView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var body: some View {
        TabView {
            ListenView().miniPlayerDock()
                .tabItem { Label("Listen", systemImage: "sparkles") }
            LibraryView().miniPlayerDock()
                .tabItem { Label("Library", systemImage: "music.note.list") }
            SearchTabView().miniPlayerDock()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
    }
}

private extension View {
    func miniPlayerDock() -> some View {
        safeAreaInset(edge: .bottom) { MiniPlayer() }
    }
}
```

Also ensure `MiniPlayer` collapses to **zero size when nothing is playing** (return `EmptyView()` / no frame when `playerVM.currentTrack == nil`), so the inset reserves no space and doesn't push tab content up when idle.

### Verification gate
Build + smoke: start playback, confirm the mini-player sits **above** a fully-visible, tappable tab bar; switching tabs works while audio plays; with nothing playing, no empty strip appears above the tab bar. Check Dynamic Type and that the mini-player + tab bar don't overlap at the largest sizes.

### Acceptance
The tab bar is always visible and tappable during playback; the mini-player docks above it.

---

## TASK 7 — "Music for You" / "Books for You" duplicated under Music and Books

### Problem
In `ParsoRadio/Views/Listen/ListenView.swift`, the "For You" channels are shown by `ForYouSection` (filter `category == "For You"`, line ~65), **and** the per-kind sections show `Channel.defaults.filter { $0.mediaKind == section.id }` (line ~47). A "Music for You" channel has `category == "For You"` *and* `mediaKind == .music`, so it appears in both the For You section and the Music section (likewise "Books for You" under Books).

### Fix
Exclude channels that already have a dedicated section from the per-kind sections. At minimum exclude `category == "For You"`; for consistency also exclude any category rendered by another dedicated section (e.g. the "Curated" live-music set shown by `LiveMusicSection`), so nothing double-lists:

```swift
private func channelsSection(for section: LibrarySection) -> some View {
    // Categories that have their own dedicated section above/below — keep them
    // out of the generic per-kind lists so nothing appears twice.
    let dedicated: Set<String> = ["For You", "Curated"]
    let channels = Channel.defaults.filter {
        $0.mediaKind == section.id && !dedicated.contains($0.category)
    }
    ...
}
```
(If `LiveMusicSection` does not actually duplicate with a kind section in practice, keep just `["For You"]` — but verify by eye that no channel appears under both a kind section and a dedicated section.)

### Verification gate
Build + smoke the Listen tab: each "…for You" channel appears once (in For You only); no channel appears under both For You and Music/Books; the per-kind sections still list everything else.

### Acceptance
No channel is listed in more than one Listen section.

---

## TASK 8 — Local-file tracks in playlists don't play (diagnostic + fix)

### What is already known to be correct (do NOT re-investigate these)
Static inspection confirms the storage/resolution chain is internally consistent, so the bug is **not** in these:
- `LocalFileImportService.processAudioFile` copies the file to `FileStorageService.localURL(for: destId)` = `Documents/audio/<id>.<ext>`, sets `source = "local"`, `isLocal = true`, `localFilePath = dest.path`, and `saveTracks([track])`.
- `DatabaseService.saveTracks` persists `source`, `is_local`, `local_file_path`, `stream_url`; `addTrack(_:toPlaylist:)` calls `saveTracks` before inserting the join row.
- `fetchTracks(forPlaylist:)` plucks each track from the `tracks` table and `rowToTrack(_:)` rehydrates `source` / `localFilePath` / `isLocal`.
- `Track.resolvedLocalURL` resolves by **filename** against the current `Documents/audio/` (robust to stale absolute sandbox paths), and `playTrack` routes local tracks through it (it throws `URLError(.fileDoesNotExist)` if it returns nil).
- `PlaylistDetailView` starts playback via `playerVM.loadPlaylist(_:startingAt:)` / `resumePlaylist(_:)` directly (no clobbering `load(channel:)`).

### Reproduce, then instrument the chain
This is a runtime failure; reproduce on device/simulator: import a local audio file into a playlist, open the playlist, tap the track. Add temporary `os_log`/`print` diagnostics at each hop and find the first that misbehaves:
1. `LocalFileImportService.importFile` — is `addTrack(toPlaylist:)` actually reached, or does the dedup `guard !existingKeys.contains(key)` (line ~19) return early? (Files with no metadata get `title = filename`, `artist = "Unknown"`; two such files can collide on `title|artist` and be silently dropped from the playlist. If so, fix the dedup key to include the track id / file URL so distinct files are never collapsed.)
2. Right after import: does the file exist at `dest.path`, and does `Track.resolvedLocalURL` return non-nil for the saved track?
3. `loadPlaylist` → log `tracks.count` from `fetchTracks(forPlaylist:)`. If it's 0 or short, the rows are being dropped — check whether `rowToTrack(_:)` returns nil for the local row (e.g. `URL(string: stream_url)` failing on an empty/relative stored value, or a typed non-optional column read failing).
4. `playTrack` local branch — log the resolved `url` and confirm `resolvedLocalURL` is non-nil at play time; then confirm the audio engine actually loads the `file://` URL (AVPlayer can fail silently on an unexpected container/codec or on a path that isn't a valid `file://` URL).

### Fix
Repair the first broken hop found. Likely candidates, in order of probability: (a) the import dedup guard dropping the file before it's added to the playlist; (b) `rowToTrack` dropping the row on an empty/invalid stored `stream_url` for locals (if so, store a valid `file://` stream URL or make `rowToTrack` tolerant for `source == "local"`); (c) the engine not receiving a proper `file://` URL. Add a regression test in `DatabaseServicePlaylistTests` / `PlaybackReliabilityTests` that round-trips a `source == "local"` track through `addTrack(toPlaylist:)` → `fetchTracks(forPlaylist:)` and asserts the rehydrated track has `isLocal == true`, a non-nil `resolvedLocalURL` (after staging a file in `Documents/audio/`), and survives `loadPlaylist`'s non-empty guard.

### Verification gate
Build + unit suite green incl. the new regression test. Smoke: import a single local file into a new playlist and play it; import several distinct local files (including some with missing/identical metadata) and confirm each is added and plays; play, advance to the next local track, and back.

### Acceptance
Local-file tracks added to a playlist play reliably, and the failure mode has a regression test.

---

## Phase 8 definition of done

- **The Now Playing screen is fully restored**: artwork + transport + favorites + share + AirPlay always present; type-specific controls (scrub/speed/sleep/chapters/book-skip/bookmark) appear per `behavior`; shuffle/repeat only for music; the player never collapses to name-only, including in playlist/album mode and while loading. Verified by manual smoke across all five content types **and** playlist mode.
- **The bottom tab bar stays visible and tappable during playback**, with the mini-player docked above it.
- **No channel appears in more than one Listen section** ("…for You" channels show only under For You).
- **Local-file tracks in playlists play reliably**, covered by a regression test.
- No duplicated method bodies between the VM and any controller.
- `PlaylistPlaybackController` exists and owns playlist playback; book-nav lives in `WholeItemController`; autosave lives in `SessionRestoreController`.
- `PlayerViewModel` holds only transport / queue / stall / shuffle-repeat toggles / kids-assertions and is **under ~1,300 lines**; everything else forwards to a controller.
- `NowPlayingView.swift` deleted; no stale references to removed types.
- All invariants in §0 intact; full unit suite green; CI still ships.
