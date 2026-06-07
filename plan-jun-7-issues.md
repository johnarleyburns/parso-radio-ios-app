# plan-jun-7-issues.md

## Bug fixes and feature improvements

### 1. Clear streaming cache UI lock
**Root cause**: `CacheManager.clearStreamingCache()` is synchronous `FileManager.removeItem(at:)` called from a `Button` action on the main thread. Blocks UI for seconds.
**Fix**: Make `clearStreamingCache()` async via `Task.detached`. Also make `clearDownloads()` async. Same for `evictIfNeeded` if called frequently.
**Files**: `CacheManager.swift`
**UI test**: Tap "Clear Streaming Cache" → spinner appears briefly → cache cleared without UI hang.

### 2. Default cache limit → 250 MB
**Fix**: Change `@AppStorage("maxCacheMB")` default from `1024` to `250`.
**Files**: `SettingsView.swift`

### 3. Settings: show downloaded tracks by playlist for selective clearing
**Fix**: In Settings → Storage section, add a disclosure group "Downloads by Playlist" listing each playlist with downloaded tracks + the count. Tapping a row deletes downloads for that playlist only. Also show standalone downloaded tracks (not in any playlist).
**Files**: `SettingsView.swift`, `DatabaseService.swift` (new query: `fetchDownloadedTrackIdsForPlaylist`), `OfflineDownloadService.swift`
**UI test**: Navigate to Settings → Storage → verify playlist rows appear → tap to clear → verify count drops.

### 4. Badge floating (no layout impact)
**Root cause**: Supporter badge `HStack` is a child of the outer `VStack`, consuming vertical space and pushing the click wheel down.
**Fix**: Remove the HStack. Use `.overlay(alignment: .bottomTrailing)` on the `screenPanel` with a negative bottom offset to float the badge into the gap between the screen panel and the wheel.
**Files**: `iPodView.swift` lines 120-132

### 5. Podcast count mismatch on category page
**Root cause**: `@StateObject private var podcastStore = PodcastSubscriptionStore.shared` — `@StateObject` is wrong for a singleton. `@ObservedObject` is correct. Also async `loadFromDB()` may not complete before first render.
**Fix**: Change `@StateObject` to `@ObservedObject` in `ChannelListScreen`. Also: `PodcastSubscriptionStore` already `@Published` on `subscriptions`, so the view will react. Add `.task { await podcastStore.loadFromDB() }` as a safety net.
**Files**: `ChannelListScreen.swift`, `PodcastSubscriptionStore.swift`
**UI test**: Navigate to Podcasts → add a podcast → return to list → verify count increased.

### 6. Remove search button on podcasts toolbar
**Fix**: Remove the magnifying glass button from `ChannelListScreen` toolbar. Keep only the `+` button. `PodcastAddView` already has search inside it.
**Files**: `ChannelListScreen.swift`

### 7. Podcast search filtering
**Root cause**: iTunes Search API with `entity=podcast` already filters to podcasts, but some results may have empty/invalid `feedUrl` fields.
**Fix**: Filter search results in `PodcastSearchService` to drop results with empty `feedURL` or results whose `trackCount` is 0.
**Files**: `PodcastSearchService.swift`

### 8. Podcast info view enriched
**Root cause**: `ChannelInfoView` only shows static Channel fields. No dynamic data from DB.
**Fix**: 
- Add `AsyncImage` for `channel.imageURL` in header (fallback to SF Symbol)
- Query `DatabaseService` for episode count per channel
- Show feed URL prominently for podcast channels
- Show `channel.imageURL` if available
- Add `description` field to `PodcastSubscription` struct, parsed from RSS `<description>` tag on subscribe
**Files**: `ChannelInfoView.swift`, `DatabaseService.swift`, `PodcastSubscriptionStore.swift`, `PodcastRSSService.swift`
**UI test**: Open ChannelInfo for a podcast → verify artwork shows, episode count shown, feed URL visible.

### 9. Podcast channel image in track area
**Root cause**: `Channel.imageURL` exists but artwork pipeline never reads it. Only per-track `artworkURLString` is used.
**Fix**: In `PlayerViewModel.playTrack()` artwork fetch Task, if `ArtworkService.artwork(for: track)` returns nil, fall back to `currentChannel?.imageURL`. Add `artwork(fromURL:)` overload to `ArtworkService`.
**Files**: `PlayerViewModel.swift`, `ArtworkService.swift`
**UI test**: Play a podcast → verify artwork appears in track area (full-bleed background).

### 10. Curation export broken
**Root cause A**: First tap hits a `Button` which triggers async `prepareExport()`, which swaps the button to a `ShareLink`. User must tap again.
**Fix**: Load export data eagerly in `.task` so `ShareLink` is always shown when approved tracks exist.
**Root cause B**: `rejected: []` is hardcoded; `fetchRejectedTracks` never called.
**Root cause C**: `fetchApprovedTracks` JOINs `tracks` table — if tracks were evicted, approved verdicts silently drop from export.
**Fix B**: Call `fetchRejectedTracks` too and populate `rejected` array.
**Fix C**: Fetch track metadata from `curation` table directly if `tracks` JOIN misses, or denormalize title/creator/duration into `curation` table at verdict time.
**Files**: `ChannelInfoView.swift`, `DatabaseService.swift`
**UI test**: Curate a channel → approve some tracks → open ChannelInfo → tap Export → verify JSON file contains approved + rejected lists with correct titles.

### 11. Curated channel image upload
**Feature**: Add ability to set a custom image for curated channels, shown in the track area as fallback when no per-track artwork exists.
**Plan**:
- Add `imageData: Data?` to `ChannelDefinition` struct in `CustomChannelsStore.swift`
- Add `PhotosPicker` or `ImagePicker` in `ChannelInfoView` for curated channels
- Persist image as JPEG in `Documents/curated-channels/<id>.png` alongside the JSON file
- Export: include the image in the Share (use `UIActivityItemProvider` for multi-item share or export as base64 in JSON if smaller)
- CLI tool: accept `--image` flag to copy/import an image file alongside JSON
**Files**: `CustomChannelsStore.swift`, `ChannelInfoView.swift`, `ChannelDefinition`, `Tools/merge-curation/main.swift`
**UI test**: Open ChannelInfo for a curated channel → tap "Set Channel Image" → pick from photo library → verify image appears in track area when playing that channel.

### 12. Edit channel icon after creation + bigger icon set
**Feature**: Allow users to change a curated channel's icon from ChannelInfoView (or the curator). Expand icon choices beyond the current ~23 SF Symbols.
**Plan**:
- Extend the icon picker from `CuratedChannelsListView` (the 23 icons in `NewChannelSheet`) into a reusable `IconPickerView`
- Show it as a sheet from `ChannelInfoView` for curated channels
- **Bigger icon set**: Add ~60 more SF Symbols grouped by category (music, nature, books, science, people, places, tech, objects). Icons should be visually distinct.
- Add "Edit Icon" button in `ChannelInfoView` alongside "Curate this Channel" and "Export this Channel"
- Update `CustomChannelsStore.updateIcon(chId:newIcon:)` — already exists
**Files**: `ChannelInfoView.swift`, `CuratedChannelsListView.swift`, new `IconPickerView.swift`
**New icons**: 
  - Music: `music.quarternote.3`, `guitars.fill`, `pianokeys`, `headphones`, `speaker.wave.3`
  - Nature: `tree.fill`, `mountain.2`, `water.waves`, `flame.fill`, `leaf.arrow.circlepath`
  - Books: `books.vertical.fill`, `text.book.closed.fill`, `book.pages.fill`, `character.book.closed`
  - Science: `atom`, `flask.fill`, `brain.head.profile`, `microscope`
  - People: `figure.walk`, `figure.mind.and.body`, `person.3.fill`, `rectangle.3.group`
  - Places: `globe.americas`, `house.fill`, `building.2.fill`, `tent.fill`
  - Tech: `ear.badge.waveform`, `radio.fill`, `antenna.radiowaves.left.and.right`, `wifi`
  - Objects: `cup.and.saucer.fill`, `clock.fill`, `theatermasks.fill`, `star.circle.fill`

### 13. CLI tool: import channel image alongside JSON
**Plan**: Add `--image` flag to `merge-curation` tool. When specified, copies the image file to the same directory as the target JSON (i.e., `Resources/curated-channels/<id>.png`). The image is NOT embedded in the JSON — it's a sidecar file referenced by filename.
**Files**: `Tools/merge-curation/Sources/merge-curation/main.swift`
**Usage**: `merge-curation merge --input exported.json --target Resources/curated-channels/guitar-classical.json --image ~/Desktop/guitar-artwork.png`

---

## Implementation order

```
Phase 1 — Quick fixes (no UX change risk):
  #2  Default cache limit → 250 MB
  #5  @StateObject → @ObservedObject (podcast count)
  #6  Remove search button

Phase 2 — Behavior fixes:
  #1  CacheManager async clear
  #7  Podcast search filter
  #10 Curation export fix (eager load + rejected array + tracks JOIN fallback)

Phase 3 — UI features:
  #3  Settings: downloads by playlist
  #4  Badge floating overlay
  #8  Podcast info enriched (episode count, artwork, feed URL)
  #9  Podcast image in track area (channel.imageURL fallback)
  #11 Curated channel image upload
  #12 Edit channel icon + bigger icon set
  #13 CLI image import

Phase 4 — Tests (local-only UI tests for each fix)
```

## Test plan

| # | Test file | Test name | What it verifies |
|---|-----------|-----------|-----------------|
| 1 | `CacheUITests.swift` | `testClearStreamingCacheNoUIHang` | Clear cache button doesn't freeze app |
| 2 | `SettingsUITests.swift` | `testCacheLimitDefaultIs250` | Picker shows 250 MB default |
| 3 | `SettingsUITests.swift` | `testDownloadedByPlaylistVisible` | Playlist download count shown |
| 4 | `PlayerUITests.swift` | `testBadgeDoesNotPushWheel` | Click wheel fully visible with badge |
| 5 | `PodcastUITests.swift` | `testPodcastCountMatchesAfterAdd` | Count updates after add/remove |
| 7 | `PodcastUITests.swift` | `testSearchReturnsOnlyPodcasts` | All results are actual podcasts |
| 8 | `ChannelInfoUITests.swift` | `testPodcastInfoShowsArtworkAndCount` | Artwork + episode count visible |
| 9 | `PlayerUITests.swift` | `testPodcastShowsArtworkInTrackArea` | Artwork appears as player background |
| 10 | `CurationUITests.swift` | `testExportContainsApprovedAndRejected` | Export JSON has both arrays with tracks |
| 11 | `CurationUITests.swift` | `testCuratedChannelImageUpload` | Image picker → image shown |
| 12 | `CurationUITests.swift` | `testEditChannelIcon` | Icon picker sheet → icon changed |
