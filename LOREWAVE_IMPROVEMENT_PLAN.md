# Lorewave Architecture Improvement Plan

## Phase 1: Decompose PlayerViewModel God Object

**Problem:** `PlayerViewModel.swift` is 2,176 lines, handling ~12 distinct concerns. Any change risks side effects.

**Solution:** Extract focused controllers, keep PlayerViewModel as a thin coordinator.

### New files to create:

| File | Responsibility | ~Lines |
|------|---------------|--------|
| `Core/Services/Playback/ChannelLoader.swift` | Multi-source dispatch, channel loading, probe multi-part items | ~300 |
| `Core/Services/Playback/PlaybackController.swift` | playTrack, advance, skip, seek, stall watchdog, retry, context token | ~400 |
| `Core/Services/Playback/PlaylistController.swift` | loadPlaylist, resumePlaylist, shufflePlaylist, advancePlaylist | ~200 |
| `Core/Services/Playback/AuditionController.swift` | auditionTrack, stopAudition, pre-audition snapshot/restore | ~150 |
| `Core/Services/SessionManager.swift` | Position save/restore, autosave bookmarks, wasPlayingOnQuit, clearHistory | ~200 |
| `Core/Services/RecommendationService.swift` | fetchRecommendations, For You queries | ~100 |

### PlayerViewModel after refactor (~500 lines):
- Holds `@Published` properties
- Delegates to focused controllers
- Coordinates between controllers (e.g. load channel → playback)
- Public API stays identical (no test breakage)

---

## Phase 2: Replace Singleton Overload with DI Container

**Problem:** 11 `.shared` singletons cause test state leakage, hidden dependencies, and tight coupling.

**Solution:** Create `AppDependencies` container, pass via `@EnvironmentObject`.

### Singletons to convert:

| Singleton | Action |
|-----------|--------|
| `KidsModeController.shared` | Move to `AppDependencies`, pass via `@EnvironmentObject` |
| `LiveCurationStore.shared` | Move to `AppDependencies` |
| `CustomChannelsStore.shared` | Move to `AppDependencies` |
| `ArtworkService.shared` | Move to `AppDependencies` |
| `AgeAssuranceService.shared` | Move to `AppDependencies` |
| `PodcastSubscriptionStore.shared` | Move to `AppDependencies` |
| `IAQueryRegistry.shared` | Move to `AppDependencies` |
| `DatabaseService.shared` | Already has injected path, remove `.shared` |
| `AppIntentBridge.shared` | Keep (needs to be globally reachable for intents) |
| `IntentDonationManager.shared` | Keep (system-level singleton) |
| `NetworkMonitor.shared` | Keep (hardware-level singleton is idiomatic) |

### New file:
- `App/AppDependencies.swift` — Single struct owning all service instances

---

## Phase 3: Add Embedded Chapter Support for Audiobooks

**Problem:** Multi-part audiobooks work only when chapters are separate files on IA. Single-file M4B/MP3 audiobooks with embedded chapter markers are not navigable.

**Solution:** Parse embedded chapter metadata from AVPlayerItem and expose in UI.

### Implementation:

1. **Model:** Add `Chapter` struct with title, startTime, duration
2. **Parser:** Add `ChapterParser` service that reads `AVMetadataItem` with keys:
   - `AVMetadataIdentifierQuickTimeUserDataChapter`
   - `AVMetadataIdentifieriTunesMetadataChapter`
   - `AVMetadataIdentifieriTunesMetadataTrackNumber` (for ordering)
3. **Storage:** Add `chapters` table to SQLite (track_id, index, title, startTime, duration)
4. **UI:** Extend `ChapterListView` to show embedded chapters (not just separate-file chapters)
5. **Navigation:** Allow tapping a chapter to seek within the current track

---

## Phase 4: Fix Lock Screen Now Playing Info

**Problem:** Lock screen info is set in `AudioPlayerService.updateNowPlayingInfo()` but:
- Artwork is only added AFTER async fetch completes (delay)
- Album title / channel name not shown
- Progress updates may be inconsistent during rapid skip
- No chapter-level info shown

### Fixes:

1. **Set artwork eagerly:** Use cached artwork from `ArtworkService.memCache` or a placeholder immediately, then update when fetch completes
2. **Add album title:** Set `MPMediaItemPropertyAlbumTitle` to channel/playlist name
3. **Add chapter info:** If embedded chapters exist, set chapter title + number
4. **Ensure progress sync:** Update `MPNowPlayingInfoPropertyElapsedPlaybackTime` on every time observer tick (currently only on seek)
5. **Set `MPNowPlayingInfoPropertyPlaybackProgress`** for iOS 16+ progress bar on lock screen
