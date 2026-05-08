# Parso Radio — Use Cases

Each use case describes an observable behavior the user expects from the app,
its current implementation status, and the tests that verify it.

---

## UC1 — First Launch

**Scenario:** The user opens the app for the very first time after installing it.

**Expected behavior:**
1. A splash / logo screen appears briefly.
2. A Terms of Service sheet is shown (required before playback).
3. After accepting, the default channel (Bach & Vivaldi — Strings) loads automatically.
4. Playback begins without the user doing anything.

**Status:** ✅ Implemented  
`SplashView` → `TermsView` → `iPodView` flow in `ParsoRadioApp.swift`.  
The `.task` modifier on `iPodView` triggers `playerVM.load(channel: pendingChannel)`.

**Tests:** `ChannelTests.testDefaultChannelCount`

---

## UC2 — App Remembers Last Channel After Restart

**Scenario:** The user was listening to "Jazz Bar" and closes/backgrounds the app.
On the next launch the app resumes on "Jazz Bar", not back to the default channel.

**Expected behavior:**
1. On any channel switch, the channel ID is persisted to `UserDefaults`.
2. On the next launch, `iPodView.pendingChannel` is initialized from that stored ID.
3. `PlayerViewModel.load()` resumes the last-played track in that channel.

**Status:** ✅ Implemented (this pass)  
`PlayerViewModel.load()` calls `UserDefaults.standard.set(channel.id, forKey: "lastChannelId")`.  
`iPodView.pendingChannel` reads `UserDefaults.standard.string(forKey: "lastChannelId")` on init.  
Track position resume was already in place via the `DatabaseService.loadPosition` call.

**Tests:** `PlayerViewModelTests.testLastChannelIdSavedOnLoad`

---

## UC3 — Navigate to Previous and Next Track

**Scenario:** The user is listening to a track and wants to go back to the one they
just heard, or skip forward to the next track.

**Expected behavior:**
- **Forward (skip):** ClickWheel forward button → skip to a new track.
- **Back when > 3 s into track:** ClickWheel back button → restart current track.
- **Back when ≤ 3 s into track:** ClickWheel back button → play the previous track.
- **Back when no history:** restart current track from the beginning.
- **Lock screen / headphone previous button:** same as back-at-start.
- **Spoken word:** back rewinds 15 s; at position ≤ 3 s, goes to previous chapter.

**Status:** ✅ Implemented (this pass)  
`PlayerViewModel` maintains a `playHistory: [Track]` stack (cap 50).  
`playTrack(_:seekTo:recordHistory:)` pushes the current track before replacing it.  
`back()` calls `playPreviousTrack()` when at the start.  
`AudioPlayerService.previousTrackCommand` wired to `onPreviousTrack` callback.

**Tests:** `PlayerViewModelTests.testBackAtStartGoesToPreviousTrack`,
`PlayerViewModelTests.testBackMidTrackRestartsCurrentTrack`,
`PlayerViewModelTests.testBackWithNoHistoryRestartsFromZero`

---

## UC4 — Tracks Play in a Shuffled, Non-Repeating Order

**Scenario:** The user listens to a channel for an extended session and never hears
the same track twice until all tracks have played.

**Expected behavior:**
- Tracks are drawn from a weighted-random pool seeded by the daily date + channel ID.
- Recently played tracks are excluded (history cap: 50).
- Order changes each day so the same session isn't repeated tomorrow.

**Status:** ✅ Implemented  
`QueueManager.nextTrack()` uses `weightedRandom(from:seed:)` with `recentIDs` exclusion.

**Tests:** `QueueManagerTests.testNoRepeatWithin50Plays`,
`QueueManagerTests.testDeterministicOrderIsSameForSameDay`

---

## UC5 — Switch Channel Without Hearing Old Track

**Scenario:** The user taps MENU, selects a different channel, and expects the old
track to stop immediately and the new channel to start loading.

**Expected behavior:**
1. Old playback stops the moment the user confirms the channel selection.
2. UI clears the track card while the new channel fetches.
3. New channel's first track begins playing.

**Status:** ✅ Implemented (this pass)  
`PlayerViewModel.load()` now calls `audioPlayer.skip(); currentTrack = nil; isPlaying = false`
before any async work begins.

**Tests:** `PlayerViewModelTests.testChannelSwitchStopsOldPlayback`

---

## UC6 — Favorites (Visited Channels Float to Top)

**Scenario:** The user visits a channel and it is automatically pinned to the top of
the channel selector under a "Favorites" section. Swiping left removes it.

**Expected behavior:**
1. Every channel the user selects via MENU is added to a persisted favorites list (MRU order, capped at 20).
2. `ChannelSelectorView` shows a "Favorites" section at the top containing visited
   channels in most-recently-used order.
3. Swipe-left on a Favorites row reveals a "Remove" button that removes it from the section.

**Status:** ✅ Implemented (this pass) — ⚠️ swipe & long-press removal broken, fix planned  
`PlayerViewModel.load()` writes visited channel IDs to `UserDefaults("visitedChannelIds")`.
`ChannelSelectorView` reads this on appear and renders a "Favorites" section at the top.
`.swipeActions(edge: .trailing)` wires up the destructive Remove action.

**Known bug:** The Favorites row is wrapped in `Button { … }.buttonStyle(.plain)`.
`.buttonStyle(.plain)` expands the touch target across the full row and swallows the
horizontal pan gesture that `.swipeActions` depends on — so swipe-left never fires.
Long-press also does nothing. **Fix (planned with UC14):** replace the `Button` wrapper
with `.contentShape(Rectangle()).onTapGesture { … }` so the swipe recogniser is no
longer blocked; additionally add `.contextMenu` so long-press surfaces a
"Remove from Favorites" option as a second path.

**Tests:** `PlayerViewModelTests.testLastChannelIdSavedOnLoad` (covers the UserDefaults pattern)

---

## UC7 — All FMA Genres Available as Channels

**Scenario:** The user opens the channel selector and sees all FMA genres as
playable channels under an "FMA" category.

**Available FMA genres (curl-verified, 40 PD+CC-BY tracks each):**
International, Blues, Jazz, Country, Pop, Instrumental, Rock, Soul-RnB,
Experimental, Folk, Classical, Electronic, Hip-Hop, Old-Time & Historic

**Status:** ✅ Implemented (this pass)  
14 dedicated FMA channels added under the "FMA" category. Root cause of
"No tracks available" also fixed: `DatabaseService.fetchTracks` now uses
confidence threshold 0.0 for tag-only channels (matching the 0.0 threshold
used during fetch), and `FMAService` always stores `metadataConfidence: 2.0`.

**Tests:** `ChannelTests.testFMACategoryHas14Channels`,
`ChannelTests.testFMAChannelsHaveValidTags`,
`FMAIntegrationTests.testFMAInternationalChannelReturnsAtLeastOnePDTrack`,
`FMAIntegrationTests.testFMAHipHopChannelReturnsAtLeastOnePDTrack`,
`DatabaseServiceTests.testLowConfidenceTracksIncludedInTagChannel`

---

## UC8 — Fast-Forward / Rewind Within a Track

**Scenario:** The user wants to skip ahead 30 seconds or back 15 seconds within the
currently playing track without changing tracks.

**Expected behavior:**
- For spoken-word channels: back = −15 s (if > 3 s into chapter), forward = +30 s.
- For music channels: back restarts track (> 3 s) or goes to previous track (≤ 3 s).

**Status:** ✅ Implemented (this pass)  
`PlayerViewModel.skip()` now differentiates by contentType:
- Spoken-word: forward skips +30 s within the chapter; if target > duration, advances to next chapter.
- Music: forward goes to next track (radio behavior, unchanged).
Back behavior was implemented in the UC3 pass (−15 s for spoken-word, restart or previous track for music).

**Tests:** `PlayerViewModelTests.testBackInSpokenWordRewinds15Seconds`

---

## UC9 — Tap Track Card to See Details

**Scenario:** The user taps the now-playing card and a popup shows full track
metadata: title, artist, composer, instruments, duration, license, source, and a deep link.

**Status:** ✅ Implemented (this pass)  
`TrackDetailView.swift` shows all metadata in a sheet. `iPodView.nowPlayingCard`
has `.onTapGesture` that sets `showTrackDetail = true` when a track is loaded.
Deep links: `archive.org/details/{id}` for IA, FMA track page derived from stream URL.

**Tests:** N/A (UI-only)

---

## UC10 — FMA Channels Grouped Under FMA Category

**Scenario:** In the channel selector, there is a clearly labeled "FMA" (Free Music
Archive) section containing only channels sourced from FMA.

**Status:** ✅ Implemented (same pass as UC7) — 14 FMA channels under "FMA" category.

---

## UC11 — LibriVox Audiobooks Category

**Scenario:** The user sees a "LibriVox Audiobooks" category with spoken-word
channels covering genres such as Greek Philosophy, Children's Books, Science
Fiction, Mystery, History, and more.

**Status:** ✅ Implemented (this pass)  
All 13 spoken-word channels renamed from "Talk & Stories" to "LibriVox Audiobooks".
Category color/gradient maps updated in iPodView, PlayerView, and ChannelListView.

**Existing spoken-word channels (LibriVox Audiobooks):**
- Greek Philosophy, Greek History, Chinese Philosophy, Chinese History
- Children's Books, French Children's Books, Spanish Children's Books
- Science Fiction, Mystery & Detection, Classic Literature, History
- French Literature, Spanish Literature

**Tests:** `ChannelTests.testSpokenWordChannelsUseLibriVoxCategory`,
`SpokenWordIntegrationTests.testGreekPhilosophyChannelReturnsAtLeastOneTrack`,
`SpokenWordIntegrationTests.testChildrensBooksChannelReturnsAtLeastOneTrack`,
`SpokenWordIntegrationTests.testScienceFictionChannelReturnsAtLeastOneTrack`

---

## UC12 — Audio Continues in Background and on Lock Screen

**Scenario:** The user locks their phone or switches to another app while a track
is playing. Audio continues uninterrupted. Lock screen / Control Center show
track metadata and media controls.

**Expected behavior:**
1. Audio keeps playing when the app is backgrounded or the screen is locked.
2. Lock screen and Control Center show title, artist, and playback rate.
3. Hardware play/pause, skip-forward, and skip-backward controls work.

**Status:** ✅ Implemented (fully fixed this pass)  
`AVAudioSession.setCategory(.playback)` + `setActive(true)` in `AudioPlayerService.init()`.  
`UIBackgroundModes: [audio, fetch]` now correctly declared as a plist array via XcodeGen
`info:` section (the previous `INFOPLIST_KEY_UIBackgroundModes` build setting was silently
ignored because UIBackgroundModes is an array type — it was never in the built plist).  
`AVAudioSession.interruptionNotification` handler resumes playback after phone calls,
Siri, notifications, or any other interruption when iOS signals `.shouldResume`.  
`AVAudioSession.routeChangeNotification` handler mirrors the iOS pause when headphones
are unplugged.  
`UIBackgroundTask` assertion in `advanceToNext()` gives iOS up to 30 s of background
CPU time to resolve the next track URL when a track ends while backgrounded.

**Tests:** `AudioPlayerServiceTests.testAudioSessionCategoryIsPlayback`

---

## UC13 — Oxford Lectures Category

**Scenario:** The user opens the channel selector and sees an "Oxford Lectures" category
with 22 channels covering Oxford University departments (Philosophy, History, Physics,
Computer Science, etc.). Tapping a channel plays open-license audio lectures.

**Expected behavior:**
1. "Oxford Lectures" section appears in the channel selector below FMA.
2. Each of the 22 channels represents one Oxford department podcast unit.
3. Selecting a channel fetches lectures from `podcasts.ox.ac.uk` and begins playback.
4. Position is persisted and restored (same as LibriVox audiobooks).
5. Back = rewind 15 s; Forward = skip +30 s within the lecture.

**Status:** ✅ Implemented (this pass)  
`OxfordLecturesService.fetchTracks(unitSlug:)` performs a 3-level crawl:
unit page → series pages (parallel) → `audio.xml` RSS feeds (parallel) → `Track` objects.  
Series with only a `video.xml` feed (1 GB MP4s) are automatically skipped.  
All 22 Oxford channels use `contentType: .spokenWord` so position is persisted and
rewind/fast-forward behave like LibriVox channels.  
Oxford tracks carry `license: .ccBy` and `source: "oxford_lectures"`.  
TORCH unit slug corrected from LECTURES.md (`the-oxford-research-...` →
`oxford-research-centre-humanities-torch`, verified against the Oxford podcasts directory).

**Tests:** `ChannelTests.testOxfordLecturesCategoryHas22Channels`,
`ChannelTests.testOxfordLecturesChannelsAreSpokenWord`,
`ChannelTests.testOxfordLecturesChannelsHaveUnitSlugTag`,
`OxfordLecturesIntegrationTests.testPhilosophyChannelReturnsAtLeastOneTrack`,
`OxfordLecturesIntegrationTests.testPhysicsChannelReturnsAtLeastOneTrack`

---

## UC14 — In-Track Seek (Slider + Skip Buttons)

**Scenario:** The user is listening to a track and wants to jump to a specific moment —
either by dragging a progress slider to an arbitrary position, or by tapping standard
podcast skip buttons (−15 s / +30 s).

**Expected behavior:**
- A draggable progress slider appears in the now-playing card whenever the track duration
  is known (applies to all channel types: music, LibriVox, and Oxford Lectures).
- Dragging the slider seeks to the chosen position; the time labels update live while
  dragging so the user can see the target time before releasing.
- On release the seek fires once (not on every drag frame) to avoid jank.
- For spoken-word and Oxford Lectures channels only: two tap targets appear below the
  slider — `−15 s` (backward.15) and `+30 s` (forward.30) — matching the click wheel's
  spoken-word behavior but as visible, on-screen buttons.
- Music channels show the slider but not the ±-second buttons (the click wheel already
  provides skip-to-next and restart-track on those channels).

**Implementation notes:**
- `PlayerViewModel.seek(to:)` — new public method, wraps `audioPlayer.seek(to:)` and
  updates `currentPosition`. Existing `back()` and `skip()` refactored to call it.
- `iPodView`: `ProgressView` replaced by `Slider`; `@State var isScrubbing: Bool` flag
  prevents the 5-second `onTimeUpdate` callback from overwriting the thumb while dragging.
  Seek is committed in `onEditingChanged(false)`.
- Slider hidden until `trackDuration != nil` (same condition as the current spoken-word bar).
- **Network timeout increase:** all three services (`OxfordLecturesService`,
  `InternetArchiveService`, `FMAService`) currently use `URLSession.shared`. Track-list
  fetching should allow up to **20 seconds** per request before failing (target: 20 s
  `timeoutIntervalForRequest`, `timeoutIntervalForResource = 60 s`). A shared
  `URLSession.app` static with a custom `URLSessionConfiguration` will be used as the
  default in each service's `init(session:)`; tests still inject a custom session.
- **Oxford Lectures forward button:** Oxford channels are `contentType: .spokenWord`,
  so `PlayerViewModel.skip()` currently seeks `+30 s` within the lecture instead of
  advancing to the next one. For hour-long lectures this is effectively invisible (no
  progress bar if `trackDuration` is nil, or imperceptible if it is). Fix: in `skip()`,
  check `channel.category == "Oxford Lectures"` and branch to the music/next-track path
  instead of the `+30 s` seek path. Back (−15 s rewind) is still correct for Oxford.
  UC14's on-screen seek buttons should then show only `−15 s` for Oxford (no `+30 s`
  button), relying on the slider for arbitrary forward seeks.

**Status:** 🔲 Planned

**Tests:** `PlayerViewModelTests.testSeekUpdatesCurrentPosition`,
`PlayerViewModelTests.testOxfordForwardSkipsToNextTrack`

---

## UC16 — Classical Category (IA-sourced, curated by period and format)

**Scenario:** A "Classical" category returns to the channel selector, but with channels
designed around IA metadata that actually exists in quantity — period channels (Baroque,
Romantic, Early Music) and format/ensemble channels (Symphony, Opera, String Quartet,
Piano, Organ & Harpsichord) — instead of the broad composer+instrument combinations
that proved unreliable.

**Research findings (curl-verified against archive.org Solr):**

| Channel | IA subject query | numFound |
|---|---|---|
| Baroque | subject:"baroque" | 4,274 |
| Romantic Era | subject:"romantic" | 9,413 |
| Early Music | subject:"early music" OR subject:"renaissance" | ~2,253 |
| Symphony & Orchestra | subject:"symphony" | 7,428 |
| Opera | subject:"opera" | 17,225 |
| Chamber Music | subject:"chamber music" OR subject:"string quartet" | ~1,656 |
| Piano Classics | subject:"piano" AND (subject:"romantic" OR subject:"baroque" OR subject:"classical") | ~1,100 |
| Organ & Harpsichord | subject:"organ" OR subject:"harpsichord" | ~4,027 |

All counts are pre-license filtering; `LicenseValidator` reduces these but large pools
mean sufficient tracks remain after filtering.

**Proposed 8 period/format channels under "Classical" category:**

1. **Baroque** — `tags: ["baroque"]` — 4,274 raw items; clean subject term
2. **Romantic Era** — `tags: ["romantic"]` — 9,413 raw items
3. **Early Music** — `tags: ["early music", "renaissance"]` — OR-joined, ~2,253 items
4. **Symphony & Orchestra** — `tags: ["symphony"]` — 7,428 items; format-based
5. **Opera** — `tags: ["opera"]` — 17,225 items; noisy but LicenseValidator filters
6. **Chamber Music** — `tags: ["chamber music", "string quartet"]` — OR-joined, ~1,656 items
7. **Piano Classics** — needs AND-join: `subject:"piano"` AND one of
   `("romantic", "baroque", "classical")`; single tag "piano" returns 31k noisy items.
   Requires a new `andTags: [String]` field on Channel (AND-joined in IA query) or a
   dedicated IA fetch variant.
8. **Organ & Harpsichord** — `tags: ["organ", "harpsichord"]` — OR-joined, ~4,027 items

**Proposed 18 individual composer channels (curl-verified against IA Solr `creator:` field):**

| Channel | IA creator query | numFound (raw) |
|---|---|---|
| Johann Sebastian Bach | creator:"bach" | 1,933 |
| Wolfgang Amadeus Mozart | creator:"mozart" | 2,336 |
| Ludwig van Beethoven | creator:"beethoven" | 2,064 |
| Franz Schubert | creator:"schubert" | 1,500 |
| Robert Schumann | creator:"schumann" | 1,109 |
| Johannes Brahms | creator:"brahms" | 1,015 |
| Franz Joseph Haydn | creator:"haydn" | 1,049 |
| Frédéric Chopin | creator:"chopin" | ~600 |
| Sergei Rachmaninoff | creator:"rachmaninoff" | ~400 |
| Antonio Vivaldi | creator:"vivaldi" | ~400 |
| George Frideric Handel | creator:"handel" | ~350 |
| Georg Philipp Telemann | creator:"telemann" | ~250 |
| Franz Liszt | creator:"liszt" | ~500 |
| Felix Mendelssohn | creator:"mendelssohn" | ~300 |
| Pyotr Ilyich Tchaikovsky | creator:"tchaikovsky" | ~700 |
| Antonín Dvořák | creator:"dvorak" | ~300 |
| Claude Debussy | creator:"debussy" | ~400 |
| Edvard Grieg | creator:"grieg" | ~200 |

Skipped: Wagner, Verdi (opera-heavy, metadata contaminated by opera recordings mis-tagged
as creator); Gluck (top results were a German personality podcast, not classical music).
Creator-only queries are used (not `subject:`) — more reliable for composer channels.
QueueManager pool expansion via `ComposerMap.similarity` provides fallback when primary
creator pool runs thin.

**ComposerMap extensions needed:**
Current entries: bach, vivaldi, chopin, rachmaninoff.
New entries to add (14): mozart, beethoven, schubert, schumann, brahms, haydn, handel,
telemann, liszt, mendelssohn, tchaikovsky, dvorak, debussy, grieg — each with appropriate
aliases and similar-composer mappings.

**Implementation notes:**
- Period/format channels 1–6, 8 use the existing tag-channel fetch path
  (`else if channel.composers.isEmpty`) and existing OR-join in `InternetArchiveService`.
- Channel 7 (Piano Classics) needs `andTags: [String]` on Channel (AND-joined in Solr).
- The 18 composer channels use the existing `else { // composer channels }` branch in
  `PlayerViewModel.load()` — **this branch must NOT be deleted in UC15**.
- `Channel` entries for composer channels: `composers: ["mozart"]`, `instruments: []`,
  `tags: []`, `category: "Classical"` — same pattern as existing bach/vivaldi entries.
- FMA overlap: FMA returns [] for composer-based queries (no `creator:` in FMA API);
  no contamination risk for composer channels.
- `testDefaultChannelCount` after both UC15 and UC16: 49 (from UC15) + 8 period/format
  + 18 composer = **75 channels**.

**Status:** 🔲 Planned

**Tests:** `ChannelTests.testClassicalCategoryHas26Channels`,
`ChannelTests.testDefaultChannelCount` (75 after UC15 + UC16),
`ChannelTests.testMozartChannelDefinition`, `ChannelTests.testBeethovenChannelDefinition`

---

## UC17 — Tap Responsiveness (Click Wheel and List Rows Require Multiple Taps)

**Scenario:** The user frequently needs 2–3 taps on the click wheel or channel list rows
before the action fires. It happens on the wheel (MENU, play/pause, skip, back) and in
the channel selector list.

**Root causes identified:**

1. **Click Wheel — child views swallow `SpatialTapGesture`.**
   The `ZStack` has `.gesture(SpatialTapGesture())` on the outermost view, but the inner
   `Circle`, `Text("MENU")`, and three `Image` labels sit on top in the ZStack and
   participate in hit-testing by default. SwiftUI walks the view tree top-down; these
   children consume the touch event before it reaches the ZStack's gesture handler.
   The first tap is silently eaten by a child view with no gesture — the second lands on
   the outer ring (which the children don't cover) and fires correctly.
   **Fix:** add `.allowsHitTesting(false)` to the inner circle, text label, and all three
   image labels so every tap flows through to the ZStack's gesture.

2. **List rows — `Button { }.buttonStyle(.plain)` gesture conflict.**
   All rows in `ChannelSelectorView` (favorites and category rows) are wrapped in
   `Button { onSelect(_:) }.buttonStyle(.plain)`. SwiftUI's `List` applies its own
   internal gesture recognizers for scrolling and swipe actions; `.plain` buttonStyle
   expands the touch target to fill the row and competes with those recognizers. The first
   tap arms the button highlight state without firing; the second tap fires the action.
   **Fix:** same as the UC6 favorites fix — replace `Button` with `.contentShape(Rectangle())`
   + `.onTapGesture` on both the favorites rows and all category rows.

**Status:** 🔲 Planned (fix 1 in `iPodView.swift` ClickWheel; fix 2 in `ChannelSelectorView.swift`)

**Tests:** N/A (UI gesture behaviour — manual verification)

## UC15 — Channel Set Simplification (Remove Unreliable IA Music Channels)

**Scenario:** The channel selector shows only channels that work reliably. The six
Internet Archive music categories (Classical, Jazz & Blues, Rock & Country, Vibes,
Electronic & Beats, Pop & World) are removed because IA Solr results are inconsistent —
tracks fail to load, metadata is poor, and the channels do not provide a reliable listening
experience. The remaining categories (FMA, LibriVox Audiobooks, Oxford Lectures, Favorites)
all use curated sources with predictable behaviour.

**Expected behavior:**
- Channel selector shows exactly three permanent categories: FMA, LibriVox Audiobooks,
  Oxford Lectures. Favorites appears at the top when any channel has been visited.
- No Classical, Jazz & Blues, Rock & Country, Vibes, Electronic & Beats, or Pop & World
  category is visible.

**Channels removed (21 total):**

| Category (removed) | Channels |
|---|---|
| Classical | bach-vivaldi-strings, chopin-rachmaninoff-piano, classical, ambient |
| Jazz & Blues | jazz-bar, blues, jazz-piano |
| Rock & Country | rock, country, folk, old-time-roots |
| Vibes | soft-cafe, study-focus |
| Electronic & Beats | electronic, hip-hop, experimental, instrumental |
| Pop & World | pop, world-music, soul-rnb, spanish-guitar |

**Channels kept (49 total):** 14 FMA + 13 LibriVox Audiobooks + 22 Oxford Lectures.
(After UC16 adds Classical channels, the final total becomes 75.)

**Implementation notes:**
- `Channel.swift`: delete all 21 entries above.
- `PlayerViewModel.load()`: the `else { // composer channels }` branch (Bach/Vivaldi etc.)
  **must be kept** — UC16 adds 18 new individual composer channels that use exactly this path.
  The `else if channel.composers.isEmpty` tag-channel branch also remains (FMA and Classical
  period/format channels use it).
- `ChannelListView.swift` / `iPodView.swift`: category gradient and progressTint cases for
  the six removed categories become dead code; clean them up.
- **Test deletions in `ChannelTests.swift`** (12 methods reference removed channels):
  `testBachVivaldiChannelDefinition`, `testChopinRachmaninoffChannelDefinition`,
  `testChannelMatchesComposerAndInstrument`, `testTagChannelMatchesByTag`,
  `testJazzPianoChannelDefinition`, `testJazzPianoMatchesOnlyPianoJazz`,
  `testSoulRnbChannelDefinition`, `testOldTimeRootsChannelDefinition`,
  `testTagChannelDoesNotMatchWrongGenre`, `testSoftCafeTagsUpdated`,
  `testStudyFocusTagsUpdated`, `testSoftCafeMatchesByUpdatedTags`.
  Count updated 70 → 49. A replacement `testFMATagChannelMatchesByTag` (using `fma-jazz`)
  preserves tag-matching coverage.
- **Test deletions / rewrites in `InternetArchiveIntegrationTests.swift`**:
  `testBachVivaldiStringsChannelReturnsAtLeastOnTrack`,
  `testChopinRachmaninoffPianoChannelReturnsAtLeastOneTrack`,
  `testClassicalTagChannelReturnsAtLeastOneTrack`,
  `testAmbientTagChannelReturnsAtLeastOneTrack`,
  `testMusopenChopinReturnsAtLeastOneTrack` → deleted.
  `testResolveAudioURLReturnsPlayableFileURL` → rewritten to use a LibriVox channel.
- **Test rewrites in `FMAIntegrationTests`** (tests that referenced removed non-FMA channels
  by id): `testClassicalChannelReturnsAtLeastOnePDTrack` → `fma-classical`,
  `testAmbientChannelReturnsAtLeastOnePDTrack` → deleted,
  `testJazzBarChannelReturnsAtLeastOnePDTrack` → `fma-jazz`,
  `testRockChannelReturnsAtLeastOnePDTrack` → `fma-rock`,
  `testSoulRnbChannelReturnsAtLeastOnePDTrack` → `fma-soul-rnb`,
  `testOldTimeRootsChannelReturnsAtLeastOnePDTrack` → `fma-old-time`,
  `testStreamURLRedirectsToMp3` → `fma-classical`.

**Status:** 🔲 Planned

**Tests:** `ChannelTests.testDefaultChannelCount` (49), `ChannelTests.testFMACategoryHas14Channels`,
`ChannelTests.testFMATagChannelMatchesByTag` (new)

---

## UC18 — Wrong-Channel Track Contamination Fix

**Scenario:** The user switches to an FMA jazz channel and hears a track from
Internet Archive instead of Free Music Archive. Tracks from previously visited channels
bleed into the current channel's queue.

**Root cause:**
`DatabaseService.fetchTracks(forChannel:)` queries the global `tracks` table and filters
by composer + confidence + `channel.matches()`. It does **not** filter by `source`. Once
both FMA and IA tracks tagged `"jazz"` are in the DB (because the user has visited both
an FMA jazz channel and an old IA jazz channel), `QueueManager.nextTrack()` draws from
the mixed pool and can return IA tracks for an FMA channel and vice versa.

Confirmed by reading `DatabaseService.fetchTracks(forChannel:)` (line 135):
```swift
let result = rows.compactMap(self.rowToTrack).filter { channel.matches($0) }
```
`channel.matches()` checks tags/composers/instruments but has no `source` field — so any
track with matching tags passes, regardless of which service fetched it.

**Fix:**
Add `preferredSource: String?` to the `Channel` model (default `nil`). Set it on all
channels that have a definitive source affinity:

| Category | preferredSource |
|---|---|
| FMA | `"fma"` |
| LibriVox Audiobooks | `"internet_archive"` |
| Oxford Lectures | `"oxford_lectures"` |
| Classical (period/format, UC16) | `"internet_archive"` |
| Classical (composer, UC16) | `"internet_archive"` |

In `DatabaseService.fetchTracks(forChannel:)`, add a source filter when set:
```swift
if let src = channel.preferredSource {
    query = query.filter(self.colSource == src)
}
```
No DB schema change is needed (the `source` column already exists). The filter is applied
before `channel.matches()` and removes cross-source contamination at the query level.

**Implementation notes:**
- `Channel.swift`: add `let preferredSource: String?` initializer parameter (default `nil`
  for backward-compatibility with existing `Channel(id:name:...)` call sites).
- `Channel.swift` Codable: add `preferredSource` to `CodingKeys`.
- `DatabaseService.fetchTracks(forChannel:)`: insert source filter after the confidence
  threshold filter and before the composer filter.
- `QueueManager.nextTrack()`: no changes needed; the fix lives entirely in the DB layer.
- The fallback tag-channel path in `QueueManager` (lines 45–56) creates a channel with
  `tags` only and no `preferredSource`, so it will still draw from the full pool if the
  primary pool is empty — this is the correct fallback behaviour.
- After UC15 removes IA music channels, the immediate risk is FMA ↔ IA contamination
  for Classical period/format channels that share genre tags with FMA channels (e.g.,
  `"baroque"` maps to FMA Classical genre). The fix eliminates this by scoping each
  channel's DB reads to its own source.

**Status:** 🔲 Planned

**Tests:** `DatabaseServiceTests.testFetchTracksFiltersToPreferredSource` (new) —
saves one FMA track and one IA track with matching tags, asserts that an FMA channel
returns only the FMA track.

---

## UC19 — App Icon: Parso Logo + Radio Wave Overlay

**Scenario:** The app icon uses the parso.guru brand logo overlaid with the existing
radio-wave broadcast pattern, replacing the plain "P" letter.

**Design:**
- **Background:** dark navy #0f172a (same as current icon)
- **Radio waves:** the existing light-blue (#60a5fa) broadcast pattern (dot + 3 concentric
  arcs pointing right), centered at the same position as the current icon — no change here
- **Parso.guru 2×2 grid** (replaces the white "P"):
  - The parso.guru header SVG has four 25×25 rounded squares in a 2×2 layout (100×100 viewBox)
  - `logo-main` = #0f172a (dark navy) — adapted to **white** so it's visible on dark background
  - `logo-accent` = #2563eb (brand blue)
  - Layout: top-left (white), top-right (blue), bottom-left (blue 60%), bottom-right (white 90%)
  - Two short white connecting strokes between adjacent squares (horizontal between top pair,
    vertical between left pair) — faithful to the parso.guru SVG
- The radio waves sit in the same spatial position as before; the 2×2 grid occupies the
  right-center of the icon where the "P" was

**Implementation:**
- Generate `AppIcon-1024.png` via a Python/Pillow script (no Inkscape/cairosvg required)
- Arc math: broadcast center at (330, 512); arcs at radii 115/215/315px spanning ±65° from
  horizontal, SVG-equivalent: `M x1 y1 A r r 0 0 1 x1 y2` (small arc, clockwise, right-facing)
- Grid position: top-left corner at (600, 412), squares 90×90px, gap 20px
- Replace `ParsoRadio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`

**Status:** 🔲 Planned

**Tests:** `AppIconTests.testAppIconAssetExistsInBundle` — asserts `UIImage(named: "AppIcon")`
is non-nil; fails if the PNG is corrupt or missing from the asset catalog.
