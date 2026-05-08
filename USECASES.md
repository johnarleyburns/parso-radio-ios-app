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
the channel selector under a "Favorites" section. Long-pressing removes it.

**Expected behavior:**
1. Every channel the user selects via MENU is appended to a persisted favorites list.
2. `ChannelSelectorView` shows a "Favorites" section at the top containing visited
   channels in most-recently-used order.
3. Long-pressing a channel in Favorites removes it from that section.

**Status:** 🔲 Not yet implemented  
Planned: persist visited channel IDs to `UserDefaults` in `PlayerViewModel.load()`.
`ChannelSelectorView` needs a Favorites section and a `.contextMenu` for removal.

**Tests:** Planned

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
- For spoken-word channels: back = −15 s, forward = +30 s within the chapter.
- For music channels: in-track scrubbing via a ProgressView slider (to be added).

**Status:** 🟡 Partial  
Spoken-word back (−15 s) is implemented. Forward skip within a track and music
scrubbing require additional UI (scrubber, or ClickWheel gesture).

**Tests:** Planned

---

## UC9 — Tap Track Card to See Details

**Scenario:** The user taps the now-playing card and a popup shows full track
metadata: title, artist, album, license, source, and a direct link.

**Status:** 🔲 Not yet implemented  
Planned: wrap `nowPlayingCard` in a `Button` that sets a `showTrackDetail` state,
then present a `TrackDetailSheet`.

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

**Status:** ✅ Implemented  
`AVAudioSession.setCategory(.playback)` in `AudioPlayerService.init()` enables
background audio. `UIBackgroundModes: "audio fetch"` is declared in `project.yml`.
`MPRemoteCommandCenter` and `MPNowPlayingInfoCenter` are fully wired up.
Lock screen previous-track button was enabled in this pass.

**Tests:** `AudioPlayerServiceTests.testAudioSessionCategoryIsPlayback`
