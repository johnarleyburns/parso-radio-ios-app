# Lorewave — Per-Kind Player Redesign Handoff

**Repo:** `johnarleyburns/parso-radio-ios-app` · **Scheme:** `ParsoMusic` · **Target:** iOS 17+, SwiftUI/MVVM · **Player:** `ParsoRadio/Views/Player/`
**Status:** Design approved. Conventional SwiftUI (no Liquid Glass). Implement in the ordered tasks below.

Two problems to solve:
1. **Too busy.** `NowPlayingSheet` renders ~13 controls for every kind (favorite, share, archive link, AirPlay, add-to-playlist, album tracks, sleep, shuffle, repeat, speed, chapters, bookmark + transport), gated only by a few flags.
2. **Ambiguous `<<` / `>>`.** The transport row shows up to **three different "back" semantics side by side** — `backward.end.fill` (previous book), `backward.fill` (previous track/chapter), `gobackward.10` (jog −10s) — with the jog and previous-track buttons adjacent and visually near-identical. Users can't tell "within this book" from "to a different book."

The fix is a **scope grammar** (below) plus **removing the competing control per kind**, so the buttons flanking play can only ever mean one thing on any single screen. Then trim each kind to its common controls and move the rest to a single nav-bar overflow.

---

## Ground truth (verified against `main`)

- **Player shell:** `NowPlayingSheet.swift` (~430 lines). Shared chrome = artwork + track info + dismiss chevron + error/loading. The differing part is `bottomControls`.
- **Transport:** `TransportControls.swift` — where the seek-vs-skip ambiguity lives.
- **Reusable components (KEEP and reuse):** `ScrubBar(tint:)`, `SpeedControl(showLabel:)`, `ChapterButton(showLabel:)` (auto-labels "Chapters"/"Lectures" by `mediaKind`), `BookmarkButton(showLabel:)`, `AirPlayButton()`, `ChapterListView()`.
- **Behavior is already modeled per kind** in `MediaKind.swift` → `MediaKind.behavior`. Honor these flags (today the scrub bar + jog buttons render for *every* kind, ignoring `showsScrubbableProgress`):

| flag | music | audiobook | podcast | lecture | ambient |
|---|:--:|:--:|:--:|:--:|:--:|
| `queueStyle` | shuffledPool | sequentialInOrder | sequentialNewestFirst | sequentialInOrder | singleLoop |
| `allowsShuffleToggle` | yes | – | – | – | – |
| `showsScrubbableProgress` | – | yes | yes | yes | – |
| `supportsChapters` | – | yes | – | yes | – |
| `supportsSpeedControl` | – | yes | yes | yes | – |
| `supportsSleepTimer` | yes | yes | yes | yes | yes |
| `supportsBookSkip` | – | yes | – | yes | – |
| `supportsBookmarks` | – | yes | yes | yes | yes* |
| `supportsTransportNavigation` | yes | yes | yes | yes | – |

\* Ambient's bookmark flag is set but bookmarking a loop is meaningless — drop it from the ambient UI (optionally set the flag to `false` in `MediaKind.swift`).

- **Verified `PlayerViewModel` API (all exist, signatures as written here):**
  `togglePlayPause()`, `skip()` (next track), `goToPreviousTrack() async`, `seek(to:)`, `seekBy(_ delta: Double)`, `skipToNextBook() async`, `skipToPreviousBook() async`, `toggleShuffle()`, `toggleRepeat()`, `setPlaybackRate(_:)`, `startSleepTimer(minutes:)`, `setSleepAtEndOfTrack(_:)`, `cancelSleepTimer()`, `addBookmarkAtCurrentPosition(label:) async`.
  State: `isPlaying`, `isLoading`, `loadingMessage`, `currentPosition`, `trackDuration`, `timeLeftInBook`, `shuffleMode`, `repeatMode` (`AudioPlayerService.RepeatMode`, `.off`/`.one`), `playbackRate`, `isSleepTimerActive`, `currentTrack`, `currentChannel`, `currentArtwork`, `currentTrackIsMultiPart`.
- **`Channel.mediaKind`** computed in `MediaKind+Resolve.swift`. **`ChannelCategoryStyle.color(for:)`** gives the per-category tint.

---

## The scope grammar (the core fix — applies everywhere)

Three navigation scopes, three **distinct** visual treatments, never adjacent:

| Scope | Meaning | Icons | Placement |
|---|---|---|---|
| **Jog** | move *within* the current item (± seconds) | `gobackward.15` / `goforward.30` (circular) | flanks play/pause — primary transport |
| **Item step** | move *between* tracks (music only) | `backward.fill` / `forward.fill` | flanks play/pause — **music only** |
| **Section / work** | between chapters · episodes · books · series | a **list** (`ChapterButton` → sheet) or labeled overflow items | secondary cluster / nav-bar overflow — **never flanking play** |

The rule that kills the ambiguity: **on any one screen, only one of {Jog, Item step} is present next to play.**
- Music has no within-track jog → flanking buttons are `backward.fill`/`forward.fill` = prev/next track. Unambiguous (no jog present).
- Audiobook / podcast / lecture have no track-step buttons on the main surface → flanking buttons are `gobackward.15`/`goforward.30` = jog only. Chapter/episode/book/series navigation is a list (Chapters) or an overflow item, **never** a play-flanking arrow.

`backward.fill`/`backward.end.fill` and `gobackward.15` must **never** appear on the same screen again.

---

## Architecture

Keep `NowPlayingSheet` as the **shared shell** (artwork, title block, dismiss, error/loading, and a single nav-bar overflow `…` menu). Replace `bottomControls` with a `mediaKind` switch into **per-kind control views**:

```
NowPlayingSheet (shell)
 ├─ artwork / trackInfo / dismiss / error        (shared, kept)
 ├─ toolbar: dismiss (leading) · overflow … (trailing)   ← rare actions live here
 └─ controls  →  switch mediaKind {
        .music     → MusicControls
        .audiobook → SpokenControls(isLecture: false)
        .lecture   → SpokenControls(isLecture: true)     ← audiobook + lecture share one view
        .podcast   → PodcastControls
        .ambient   → AmbientControls
    }
```

Audiobook and lecture share `SpokenControls` (identical behavior; only the "Chapters"/"Lectures" and "Book"/"Series" labels differ, already handled by `ChapterButton` + a flag).

---

## Per-kind designs

Legend: **[keep on surface]**, `→ overflow` (nav-bar `…`), ~~removed~~.

### 1 · Music — radio-style shuffle pool
No within-track jog, no scrub (honor `showsScrubbableProgress = false`). Flanking = prev/next **track**.
```
            Title / Artist
   shuffle  ◀◀   ( ▶|| )   ▶▶  repeat        prev/next TRACK · filled play
   sleep   airplay
   … (nav bar): favorite · add to playlist · share · view on archive.org
```
- **Keep:** prev track (`backward.fill` → `goToPreviousTrack()`), play/pause, next track (`forward.fill` → `skip()`), shuffle, repeat, sleep, AirPlay.
- `→ overflow`: favorite, add to playlist, share, archive.org.
- ~~scrub, jog ±, speed, chapters, bookmark, album-tracks~~.

### 2 · Audiobook (and 4 · Lecture) — sequential work with chapters
Jog only next to play. Chapter/lecture switching is the **Chapters** list. Book/series stepping is in overflow.
```
   ▬▬▬▬▬●▬▬▬▬▬▬▬▬   0:42 · Book 5h 12m left · -12:30
        ⟲15   ( ▶|| )   30⟳            jog only (circular)
        [Speed] [Chapters] [Bookmark] [Sleep]
   … (nav bar): favorite · add · share · archive · ◀ Previous book · Next book ▶  (Lecture: "series")
```
- **Keep:** scrub + elapsed/-remaining + "Book/Series … left", jog −15 (`seekBy(-15)`) / play / jog +30 (`seekBy(30)`), Speed, Chapters (→ `ChapterListView`; labels "Lectures" for lecture), Bookmark, Sleep.
- `→ overflow`: favorite, add to playlist, share, archive.org, **Previous/Next book** (`skipToPreviousBook`/`skipToNextBook`; label "series" when lecture).
- ~~prev/next-track arrows, `backward.end`/`forward.end` on surface~~ (this is the ambiguity removal).

### 3 · Podcast — sequential episodes, no chapters
Jog asymmetric (back 15 to re-hear, forward 30 to skip ads). Episode switching happens in the episode list, not the player.
```
   ▬▬▬●▬▬▬▬▬▬▬▬   3:10 · -28:05
        ⟲15   ( ▶|| )   30⟳            jog only
        [Speed] [Bookmark] [Sleep] [AirPlay]
   … (nav bar): favorite · add to playlist · share · archive.org
```
- **Keep:** scrub + times, jog −15/+30, Speed, Bookmark, Sleep, AirPlay.
- `→ overflow`: favorite, add to playlist, share, archive.org.
- ~~chapters, prev/next on surface~~.

### 5 · Ambient — single looping soundscape
Loops endlessly: no scrub, no skip, no speed. The looping visual is the hero; sleep timer is THE control.
```
   [ looping visual / procedural scene ]
              ( ▶|| )                 single large filled play/pause
        [ Sleep timer ]   [ AirPlay ]
   … (nav bar): favorite · share
```
- **Keep:** play/pause (large), Sleep (prominent), AirPlay (optional).
- `→ overflow`: favorite, share.
- ~~scrub, jog, skip, speed, chapters, bookmark~~.

A rendered mockup of all five surfaces ships alongside this doc (`player_surfaces_mockup.html`).

---

## Task 1 — Shared control bits (`ParsoRadio/Views/Player/PlayerControlBits.swift`)

```swift
import SwiftUI

/// Circular transport button. `prominent` renders a filled accent circle (play/pause).
struct TransportButton: View {
    let system: String
    var size: CGFloat = 26
    let label: String
    var prominent: Bool = false
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if prominent {
                Image(systemName: system)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size + 34, height: size + 34)
                    .background(tint, in: Circle())
            } else {
                Image(systemName: system)
                    .font(.system(size: size, weight: .semibold))
                    .frame(width: size + 22, height: size + 22)
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Scrub bar + elapsed / -remaining (+ optional "time left in book/series").
struct ScrubRow: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color
    var showTimeLeftInWork: Bool = false
    var isLecture: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ScrubBar(tint: tint)
            HStack {
                Text(playerVM.currentPosition.formattedTime)
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                if showTimeLeftInWork, let left = playerVM.timeLeftInBook {
                    Text("\(isLecture ? "Series" : "Book") \(left.formattedTime) left")
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                }
                let remaining = (playerVM.trackDuration ?? 0) - playerVM.currentPosition
                Text("-\(remaining.formattedTime)")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

struct ShuffleButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var body: some View {
        Button { playerVM.toggleShuffle() } label: {
            Image(systemName: "shuffle").font(.body)
                .foregroundStyle(playerVM.shuffleMode ? Color.accentColor : .secondary)
        }
        .accessibilityLabel(playerVM.shuffleMode ? "Shuffle on" : "Shuffle off")
    }
}

struct RepeatButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var body: some View {
        Button { playerVM.toggleRepeat() } label: {
            Image(systemName: playerVM.repeatMode == .one ? "repeat.1" : "repeat").font(.body)
                .foregroundStyle(playerVM.repeatMode == .one ? Color.accentColor : .secondary)
        }
        .accessibilityLabel(playerVM.repeatMode == .one ? "Repeat one" : "Repeat off")
    }
}

/// Sleep timer (extracted from NowPlayingSheet's inline menu).
struct SleepTimerButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var showLabel: Bool = false
    var body: some View {
        Menu {
            Button("15 minutes") { playerVM.startSleepTimer(minutes: 15) }
            Button("30 minutes") { playerVM.startSleepTimer(minutes: 30) }
            Button("45 minutes") { playerVM.startSleepTimer(minutes: 45) }
            Button("1 hour")     { playerVM.startSleepTimer(minutes: 60) }
            Divider()
            Button("End of track") { playerVM.setSleepAtEndOfTrack(true) }
            if playerVM.isSleepTimerActive {
                Divider()
                Button("Cancel timer", role: .destructive) { playerVM.cancelSleepTimer() }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: playerVM.isSleepTimerActive ? "moon.zzz.fill" : "moon.zzz").font(.title3)
                if showLabel { Text("Sleep").font(.caption2) }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(playerVM.isSleepTimerActive ? Color.accentColor : .primary)
        }
        .accessibilityLabel("Sleep timer")
    }
}
```

## Task 2 — Per-kind control views

### `ParsoRadio/Views/Player/Controls/MusicControls.swift`
```swift
import SwiftUI

struct MusicControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 22) {
                ShuffleButton()
                TransportButton(system: "backward.fill", size: 26, label: "Previous track") {
                    Task { await playerVM.goToPreviousTrack() }
                }
                TransportButton(system: playerVM.isPlaying ? "pause.fill" : "play.fill",
                                size: 30, label: playerVM.isPlaying ? "Pause" : "Play",
                                prominent: true, tint: tint) { playerVM.togglePlayPause() }
                TransportButton(system: "forward.fill", size: 26, label: "Next track") {
                    playerVM.skip()
                }
                RepeatButton()
            }
            HStack(spacing: 24) {
                SleepTimerButton()
                AirPlayButton().frame(width: 28, height: 28)
            }
        }
    }
}
```

### `ParsoRadio/Views/Player/Controls/SpokenControls.swift`  (audiobook + lecture)
```swift
import SwiftUI

struct SpokenControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color
    let isLecture: Bool

    var body: some View {
        VStack(spacing: 18) {
            ScrubRow(tint: tint, showTimeLeftInWork: true, isLecture: isLecture)

            HStack(spacing: 26) {
                TransportButton(system: "gobackward.15", size: 24, label: "Back 15 seconds") {
                    playerVM.seekBy(-15)
                }
                TransportButton(system: playerVM.isPlaying ? "pause.fill" : "play.fill",
                                size: 32, label: playerVM.isPlaying ? "Pause" : "Play",
                                prominent: true, tint: tint) { playerVM.togglePlayPause() }
                TransportButton(system: "goforward.30", size: 24, label: "Forward 30 seconds") {
                    playerVM.seekBy(30)
                }
            }

            HStack(spacing: 8) {
                SpeedControl(showLabel: true).frame(maxWidth: .infinity)
                ChapterButton(showLabel: true).frame(maxWidth: .infinity)   // "Lectures" when lecture
                BookmarkButton(showLabel: true).frame(maxWidth: .infinity)
                SleepTimerButton(showLabel: true).frame(maxWidth: .infinity)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
```

### `ParsoRadio/Views/Player/Controls/PodcastControls.swift`
```swift
import SwiftUI

struct PodcastControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        VStack(spacing: 18) {
            ScrubRow(tint: tint)

            HStack(spacing: 26) {
                TransportButton(system: "gobackward.15", size: 24, label: "Back 15 seconds") {
                    playerVM.seekBy(-15)
                }
                TransportButton(system: playerVM.isPlaying ? "pause.fill" : "play.fill",
                                size: 32, label: playerVM.isPlaying ? "Pause" : "Play",
                                prominent: true, tint: tint) { playerVM.togglePlayPause() }
                TransportButton(system: "goforward.30", size: 24, label: "Forward 30 seconds") {
                    playerVM.seekBy(30)
                }
            }

            HStack(spacing: 8) {
                SpeedControl(showLabel: true).frame(maxWidth: .infinity)
                BookmarkButton(showLabel: true).frame(maxWidth: .infinity)
                SleepTimerButton(showLabel: true).frame(maxWidth: .infinity)
                AirPlayButton().frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
```

### `ParsoRadio/Views/Player/Controls/AmbientControls.swift`
```swift
import SwiftUI

struct AmbientControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color

    var body: some View {
        VStack(spacing: 24) {
            TransportButton(system: playerVM.isPlaying ? "pause.fill" : "play.fill",
                            size: 40, label: playerVM.isPlaying ? "Pause" : "Play",
                            prominent: true, tint: tint) { playerVM.togglePlayPause() }
            HStack(spacing: 24) {
                SleepTimerButton(showLabel: true).frame(maxWidth: 130)
                AirPlayButton().frame(width: 28, height: 28)
            }
        }
    }
}
```

## Task 3 — Rework `NowPlayingSheet` (shell + overflow + switch)

1. **Replace** `bottomControls` with `controls`:

```swift
@ViewBuilder
private var controls: some View {
    let kind = playerVM.currentChannel?.mediaKind ?? .music
    let tint = ChannelCategoryStyle.color(for: channelCategory)
    Group {
        switch kind {
        case .music:     MusicControls(tint: tint)
        case .audiobook: SpokenControls(tint: tint, isLecture: false)
        case .lecture:   SpokenControls(tint: tint, isLecture: true)
        case .podcast:   PodcastControls(tint: tint)
        case .ambient:   AmbientControls(tint: tint)
        }
    }
    .disabled(playerVM.currentTrack == nil && kind != .ambient)
}
```

In `body`, swap `bottomControls` → `controls`, and add a trailing toolbar item alongside the existing dismiss button:

```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        Button { dismiss() } label: { Image(systemName: "chevron.down").fontWeight(.semibold) }
            .accessibilityIdentifier("player.dismiss")
    }
    ToolbarItem(placement: .topBarTrailing) {
        overflowMenu
    }
}
```

2. **Add the overflow menu** (holds the rare actions removed from the surface). It owns favorite + the existing `showAddToPlaylist` sheet state already on `NowPlayingSheet`:

```swift
@ViewBuilder
private var overflowMenu: some View {
    let kind = playerVM.currentChannel?.mediaKind ?? .music
    Menu {
        if let t = playerVM.currentTrack {
            let fid = t.favoriteID(for: t.favoriteKind(channel: playerVM.currentChannel))
            let isFav = favorites.favorites.contains { $0.id == fid }
            Button {
                Task { await favorites.toggle(track: t, channel: playerVM.currentChannel,
                                              positionSeconds: playerVM.currentPosition) }
            } label: { Label(isFav ? "Remove from favorites" : "Add to favorites",
                             systemImage: isFav ? "heart.fill" : "heart") }

            Button { showAddToPlaylist = true } label: { Label("Add to playlist", systemImage: "plus.circle") }

            if let shareURL = ShareURLBuilder.url(for: t) {
                ShareLink(item: shareURL) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            if t.source == "internet_archive" {
                let identifier = t.parentIdentifier ?? t.id
                let cleanId = identifier.contains("/") ? String(identifier.split(separator: "/").first ?? "") : identifier
                if let url = URL(string: "https://archive.org/details/\(cleanId)") {
                    Link(destination: url) { Label("View on archive.org", systemImage: "safari") }
                }
            }
            // Section / work stepping lives here, clearly labeled — never next to play.
            if kind == .audiobook || kind == .lecture {
                Divider()
                Button { Task { await playerVM.skipToPreviousBook() } } label: {
                    Label(kind == .lecture ? "Previous series" : "Previous book", systemImage: "backward.end")
                }
                Button { Task { await playerVM.skipToNextBook() } } label: {
                    Label(kind == .lecture ? "Next series" : "Next book", systemImage: "forward.end")
                }
            }
        }
    } label: {
        Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel("More")
}
```

3. **Delete** from `NowPlayingSheet` (now unused / moved): `bottomControls`, `stableProgressSection`, `sleepTimerMenu`, `archiveLink`, and the private `ShuffleControl` / `RepeatControl` structs. Keep `artwork`, `trackInfo`, the `showAddToPlaylist` sheet, and `.task { await favorites.loadAll() }`. (The `showAlbumTracks` sheet/state can stay if you want the album view reachable, or be removed — it is not part of the new surface.)

4. For **ambient**, the shell's `artwork` already renders `LoopingVideoView` / `ProceduralVisualizerView`. Optionally enlarge it (e.g. 300×300) when `mediaKind == .ambient` for a more immersive feel.

## Task 4 — Cleanup / flags (optional)

- Set `supportsBookmarks: false` for `.ambient` in `MediaKind.swift` (bookmarking a loop is meaningless; the ambient UI already omits it).
- `TransportControls.swift` and possibly `PlayerAccessoryButton.swift` are now unused. Confirm and delete: `grep -rn "TransportControls\|PlayerAccessoryButton" --include=*.swift .`

---

## Build & test

```bash
xcodegen generate   # after adding the new files — they are not auto-discovered
xcodebuild -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ParsoMusicTests
```

### Manual checklist
- [ ] **Disambiguation:** on audiobook, podcast, and lecture screens the only ± buttons are the circular `gobackward.15`/`goforward.30` jog. No `backward.fill`/`backward.end` appears beside play. Chapter/lecture switching is the Chapters list; book/series stepping is only in the `…` menu.
- [ ] **Music:** flanking buttons skip whole tracks; shuffle + repeat present; no scrub/jog/speed.
- [ ] **Podcast:** jog −15/+30; speed, bookmark, sleep, AirPlay; no chapters.
- [ ] **Ambient:** just a large play/pause + prominent sleep over the looping visual; nothing else.
- [ ] Each surface shows only its common controls; favorite/share/add/archive (and book/series steps) are in the `…` menu.
- [ ] VoiceOver reads jog as "Back 15 seconds"/"Forward 30 seconds" and music arrows as "Previous/Next track".
- [ ] Dynamic Type XXL doesn't clip the secondary cluster (it wraps/fits).

---

## Commit plan
1. `feat(player): shared control bits — TransportButton, ScrubRow, Sleep/Shuffle/Repeat` (Task 1)
2. `feat(player): per-kind control views (music/spoken/podcast/ambient)` (Task 2)
3. `feat(player): NowPlayingSheet shell + overflow menu + kind switch; remove busy controls` (Task 3)
4. `chore(player): flag cleanup + remove unused transport view` (Task 4, optional)

Run unit tests before each push (pre-push hook + CI run `ParsoMusicTests`).