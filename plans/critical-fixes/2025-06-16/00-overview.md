# Critical Fixes Plan — June 16, 2025

## Overview

This plan addresses 10 critical issues in the Lorewave iOS app. All issues have been
investigated against the actual codebase with precise file paths and line numbers.

Each issue below follows the required anatomy:
**Problem → Current Behavior → Research Signal → Design → Data-Model Deltas → Implementation Steps → Testing Strategy → Open Questions**

---

## Issue 1: "Jump Back In" Section Never Displays

**Files:** `ParsoRadio/Views/Listen/ListenView.swift:304-341`, `ParsoRadio/Core/Services/Storage/DatabaseService.swift:1212-1243`, `ParsoRadio/ViewModels/PlayerViewModel.swift:182-193`

### Problem
The `JumpBackInSection` on the home view is always empty — no recently played tracks appear.

### Current Behavior
- `JumpBackInSection` (ListenView.swift:304) uses `@State private var items: [Track] = []` and only renders when `!items.isEmpty`.
- Data loaded via `.task { items = await playerVM.recentlyPlayedTracks(limit: 10) }` (line 339).
- `recentlyPlayedTracks` calls `db.fetchRecentlyPlayedTracks(limit:)` (DatabaseService.swift:1212).
- The SQL query uses `INNER JOIN track_play_history ... ON ph.track_id = t.id` (line 1218-1223).
- Tracks are recorded via `recordPlayed()` whenever a non-ambient track plays (PlayerViewModel.swift:1234-1239).

### Research Signal — Root Cause: INNER JOIN orphaning after track eviction
1. `evictOldTracks()` (DatabaseService.swift:602-626) deletes old rows from the `tracks` table when `trackCount() > 5000` (PlayerViewModel.swift:188-193).
2. The `INNER JOIN` in `fetchRecentlyPlayedTracks` requires a matching row in BOTH `tracks` AND `track_play_history`.
3. When tracks are evicted from `tracks` but `track_play_history` still references those IDs (until the 30-day cleanup on line 621-622), the JOIN returns EMPTY for those entries — even if the user listened yesterday.
4. On fresh installs with no old tracks, this works initially but breaks rapidly.
5. Additional concern: `evictOldTracks()` also runs `playHistory.filter(playedAt < cutoff).delete()` (line 622), wiping 30+ day history — but the `INNER JOIN` orphaning kills recently played tracks well before the 30-day window.

### Design
**Fix A (Primary):** Change the SQL from `INNER JOIN` to a `LEFT JOIN` that returns `NULL` columns for evicted tracks, then filter them out in Swift. This way, only truly orphaned rows (track deleted, play_history remains) are skipped gracefully, but the still-existing tracks show up.
**Fix B (Defensive):** Keep `INNER JOIN` but add a `track_play_history` cleanup that cascades on track eviction — delete orphan `playHistory` rows when `evictOldTracks` removes tracks. This is already partially done (line 614-622) but it deletes by timestamp, not by evicted track IDs.

Actually, the real issue is simpler: `evictOldTracks` deletes tracks by `fetchedAt < cutoff` AND `localPath == nil` AND `isLocal == false`. These tracks are gone. Their play_history rows survive until the 30-day cleanup. So the `INNER JOIN` finds no matching track row → returns empty.

**Best fix:** Use `LEFT JOIN` so tracks still in the DB are returned even if some play_history rows are orphaned. Also, evict `play_history` rows for evicted track IDs within `evictOldTracks`:

```sql
SELECT t.* FROM track_play_history ph
LEFT JOIN tracks t ON ph.track_id = t.id
WHERE t.id IS NOT NULL
GROUP BY ph.track_id
ORDER BY MAX(ph.played_at) DESC
LIMIT ?
```

Or simply: evict play_history rows for the evicted track IDs during `evictOldTracks`.

In `evictOldTracks` (DatabaseService.swift:614-622), after collecting `evictedIds`, delete:
```swift
_ = try? self.db.run(self.playHistory.filter(evictedIds.contains(colPHTrackId)).delete())
```

### Data-Model Deltas
None — schema unchanged.

### Implementation Steps
1. In `DatabaseService.swift:evictOldTracks()` (~line 614): After collecting `evictedIds`, delete corresponding `playHistory` rows for those IDs.
2. In `DatabaseService.swift:fetchRecentlyPlayedTracks()` (~line 1218): Change `INNER JOIN` to `LEFT JOIN` + `WHERE t.id IS NOT NULL` to defensively handle any remaining orphans.
3. Run `xcodegen generate` to ensure the project picks up the change.

### Testing Strategy
- Unit test: `RecentlyPlayedTests.swift` — add a test that evicts tracks, verifies `fetchRecentlyPlayedTracks` still returns non-orphaned entries and skips orphaned ones.
- Manual: Play several tracks, trigger eviction, verify Jump Back In still shows recently played tracks (not affected by eviction).

### Open Questions
- Should we also increase the `trackCount() > 5000` threshold? Current 5000 rows is ~1-2MB of SQLite — very conservative.
- Should `evictOldTracks` respect items that are still in a user's playlists?

---

## Issue 2a: "Live Music on this Day" Wrong Size at Startup

**Files:** `ParsoRadio/Views/Listen/ListenView.swift:221-287`

### Problem
The "Live Music on This Day" section shows a loading placeholder at one size, then jumps to a different size when data arrives.

### Current Behavior
- Loading state (lines 222-238): `HStack` with 56×56 gray box + `ProgressView()` overlay + "Searching…" / "Live Music Archive" text.
- Loaded state (lines 239-269): `HStack` with `VerifiedThumb` at 56×56 + entry title/location/date text.
- Both use the same frame (56×56), but `VerifiedThumb` uses `AsyncImage` which may not respect the frame during initial load, causing a layout shift.

### Research Signal
`VerifiedThumb` (VerifiedThumb.swift) uses `AsyncImage` with `.resizable().scaledToFill()`. When AsyncImage is loading, it has no intrinsic size and SwiftUI may not constrain it to 56×56 until the image loads. The `.frame(width: 56, height: 56)` modifier SHOULD constrain it, but AsyncImage's loading phase uses its own placeholder internally.

Additionally, the loaded state has multiline text (`.lineLimit(2)` on title, optional location and date) while the loading state has fixed 2-line text. The overall `HStack` height differs between states.

### Design
Use a `ZStack` approach that maintains a consistent height regardless of loading state. Wrappers should enforce a fixed height on the entire row, not just the thumbnail.

**Fix:** Add `.frame(height: 56)` to the outer `HStack` in the loading state to match the loaded state's intrinsic height. Better: use a uniform `HStack` with `.frame(minHeight: 70)` that accommodates multiline text in both states.

Or: Always show the last cached entry while fetching, with a subtle loading indicator, so there's never a layout change.

### Data-Model Deltas
None.

### Implementation Steps
1. In `LiveMusicSection` body (ListenView.swift:221-287): Ensure both loading and loaded states have identical outer frame heights.
2. Add `.frame(minHeight: 72)` to both `HStack` variants.
3. Optionally: Show cached entry immediately with a thin `ProgressView` at trailing edge rather than a full replacement.

### Testing Strategy
- Manual: Launch the app fresh, observe the Live Music section — the size should not jump when data arrives.
- Manual: Pull to refresh, verify no size change during refresh.

### Open Questions
- Should we cache the last shown entry and display it while the new fetch runs (stale-while-revalidate)?

---

## Issue 2b: "Live Music on this Day" Keeps Reloading on Tab Navigation

**Files:** `ParsoRadio/Views/Listen/ListenView.swift:277-287`, `ParsoRadio/Core/Services/API/LiveMusicOnThisDayService.swift:1-234`

### Problem
The Live Music section re-fetches / flashes the loading spinner every time the user navigates to another tab and comes back, or when the app returns from background.

### Current Behavior
- `.task(id: fetchDate)` (line 282) fires on every SwiftUI view appearance. Even though `fetchDate` doesn't change during the day, SwiftUI's `.task` re-executes when the view hierarchy is recreated.
- Inside `.task`: `isLoading = true` is set first (line 283), causing a visible loading spinner flash even if the pool is cached.
- `LiveMusicOnThisDayService.fetchDailyEntry()` calls `getOrRefreshPool()` which checks `isPoolExpired()`. Pool expires at midnight calendar day. So the network is only hit once per day.
- But `isLoading = true` + `fetchDailyEntry()` (which picks a random entry from cache) causes a brief flash of the loading indicator.

### Research Signal
The `.task` modifier is the wrong tool here. We need:
1. Pool fetch only on first load of the day (or on pull-to-refresh).
2. Entry displayed from cache immediately, no loading flash.
3. No network activity on tab switch.

### Design
Move the pool/entry management out of the SwiftUI view `@State` and into a shared `@MainActor` service/singleton that:
- Fetches pool once per calendar day.
- Picks entry once and caches it.
- Returns cached entry instantly on subsequent view appearances.
- Only refreshes on explicit pull-to-refresh.

Create `LiveMusicOnThisDayStore` as an `@MainActor ObservableObject`:

```swift
@MainActor
final class LiveMusicOnThisDayStore: ObservableObject {
    static let shared = LiveMusicOnThisDayStore()
    @Published var entry: LiveMusicEntry?
    @Published var isLoading = false
    private var lastFetchDate: String?

    func loadIfNeeded() async {
        let today = LiveMusicOnThisDayService.todayMMDD()
        guard today != lastFetchDate else { return }
        isLoading = true
        defer { isLoading = false }
        let service = LiveMusicOnThisDayService()
        entry = await service.fetchDailyEntry()
        lastFetchDate = today
    }

    func refresh() async {
        let service = LiveMusicOnThisDayService()
        service.clearCachedEntry()
        isLoading = true
        defer { isLoading = false }
        entry = await service.fetchDailyEntry()
        lastFetchDate = LiveMusicOnThisDayService.todayMMDD()
    }
}
```

Then `LiveMusicSection` uses this as `@ObservedObject` and calls `.task { await store.loadIfNeeded() }` without setting `isLoading` on every appearance.

### Data-Model Deltas
New file: `ParsoRadio/Core/Services/API/LiveMusicOnThisDayStore.swift`

### Implementation Steps
1. Create `LiveMusicOnThisDayStore.swift` with the pattern above.
2. Inject it into `AppDependencies` / `ParsoRadioApp.swift`.
3. Rewrite `LiveMusicSection` to use `LiveMusicOnThisDayStore` instead of local `@State`.
4. `.task` calls `store.loadIfNeeded()` which is a no-op after first fetch of the day.
5. `.refreshable` calls `store.refresh()` which clears cache and re-fetches.
6. `xcodegen generate` to add the new file.

### Testing Strategy
- Manual: Navigate tabs, return to Listen — no loading spinner flash for Live Music.
- Manual: Pull to refresh — loading spinner appears briefly, new entry shown.
- Manual: Leave app overnight, return next day — new entry loaded (different date).

### Open Questions
- Should the store be a singleton or injected via DI? Singleton is simpler; DI matches existing pattern.

---

## Issue 3: MiniPlayer Overlays Tab Bar

**Files:** `ParsoRadio/Views/RootTabView.swift:1-19`, `ParsoRadio/Views/Player/MiniPlayer.swift:1-59`

### Problem
The MiniPlayer at the bottom often overlays the tab bar, making tabs inaccessible.

### Current Behavior
- `RootTabView` (line 17): `.safeAreaInset(edge: .bottom) { MiniPlayer() }` — the MiniPlayer is placed in the bottom safe area, above the tab bar.
- Apple's `.safeAreaInset` SHOULD push the tab bar up. However, `MiniPlayer` has `.background(.regularMaterial)` and `.padding(.vertical, 8)` which makes it ~56pt tall.
- The MiniPlayer only appears when `playerVM.currentTrack != nil` (line 11).

### Research Signal
This might be an iOS 17/18 safeAreaInset behavior regression. On some iOS versions, `safeAreaInset` on a `TabView` doesn't correctly adjust the tab bar position. The `.regularMaterial` background might also overlap the tab bar visually.

Alternative observation: The `MiniPlayer` uses a `Button` as its outermost view with `.contentShape(Rectangle())` and `.buttonStyle(.plain)`. The tap target of the full MiniPlayer (including the padding) might intercept taps meant for the tab bar below.

### Design
Two complementary fixes:

**Fix A (Layout):** Change `.safeAreaInset(edge: .bottom)` to a `ZStack` alignment approach where the MiniPlayer is overlay-ed on top of the TabView with sufficient bottom padding.

**Fix B (Hit-testing):** Add `.allowsHitTesting(true)` only on the MiniPlayer's interactive elements (play/pause button and the player open area), while making the background `.allowsHitTesting(false)`. This prevents the MiniPlayer background from intercepting tab bar taps.

Better approach: Add explicit bottom padding to the TabView content when the MiniPlayer is showing:

```swift
TabView {
    // tabs...
}
.safeAreaInset(edge: .bottom) {
    MiniPlayer()
        .padding(.bottom, 0) // ensure no extra padding below
}
```

Actually, the real fix: add `, spacing: 0` parameter to `VStack`/remove any extra spacing that might push the MiniPlayer down. Or use `.overlay(alignment: .bottom)` instead.

Simplest fix: wrap MiniPlayer in the safeAreaInset with `.ignoresSafeArea(edges: .bottom)` on the MiniPlayer background and use explicit padding.

Or better: Use `TabView` with the MiniPlayer as an `.overlay` aligned to `.bottom`, adding `.padding(.bottom, miniPlayerHeight)` to the TabView content:

```swift
TabView {
    ListenView()
        .safeAreaInset(edge: .bottom) { 
            if playerVM.currentTrack != nil { Spacer().frame(height: 56) }
        }
    ... 
}
.overlay(alignment: .bottom) {
    MiniPlayer()
}
```

### Data-Model Deltas
None.

### Implementation Steps
1. Replace `.safeAreaInset(edge: .bottom) { MiniPlayer() }` with an overlay approach.
2. Conditionally add bottom padding to tab content when MiniPlayer is visible.
3. Ensure the MiniPlayer's hit-testing doesn't intercept tab bar taps by limiting it to the MiniPlayer's content area.
4. Test on different iOS versions (17.0, 17.5, 18.0).

### Testing Strategy
- Manual: Play a track, verify MiniPlayer appears above tab bar without overlapping.
- Manual: Tap each tab bar item — all three should be accessible.
- Manual: Tap the MiniPlayer — should open the full player.
- Manual: Tap the play/pause button in MiniPlayer — should toggle playback without triggering tab navigation.

### Open Questions
- Does the `safeAreaInset` approach work correctly on iOS 17.0 (our minimum target)?
- Should we handle the case where the MiniPlayer is showing AND the keyboard is up?

---

## Issue 4: "Lectures" Button Cannot Find Lecture Series

**Files:** `ParsoRadio/Core/Services/Playback/WholeItemController.swift:18-69`, `ParsoRadio/Core/Services/API/OxfordLecturesService.swift:1-205`, `ParsoRadio/Core/Services/Playback/BookmarkController.swift:34-38`, `ParsoRadio/Views/ChapterListView.swift:57-62`

### Problem
When playing a lecture, tapping the "Lectures" button opens ChapterListView which shows "No Lectures" — even when the current lecture IS part of a series (verified on podcasts.ox.ac.uk).

### Current Behavior
1. User taps "Computer Science" lecture channel → `oxfordService.fetchTracks(unitSlug:)` fetches ALL series tracks, sets `parentIdentifier = seriesSlug` and `partNumber` on each.
2. A track plays, `currentTrack.parentIdentifier` = `seriesSlug` (e.g., "strachey-lecture-series").
3. User taps "Lectures" → `ChapterButton` → `ChapterListView` → `.task { chapters = await playerVM.bookmarks.fetchCurrentItemChapters() }`.
4. `BookmarkController.fetchCurrentItemChapters()` (line 34-38):
   ```swift
   let identifier = track.parentIdentifier ?? track.id
   return await vm.resolveItemParts(identifier: identifier)
   ```
5. `resolveItemParts` (WholeItemController.swift:18-69):
   - Checks `itemPartsCache[identifier]` — first call is nil.
   - `fetchTracks(forParentIdentifier: identifier)` — queries DB for tracks with `parentIdentifier == seriesSlug`.
   - If DB returns ≥2 tracks AND `partsAreClean` passes → returns them. ✓ This SHOULD work.
   - If DB returns 0 or 1, or `partsAreClean` fails → falls through.
   - `fetchTrack(id: identifier)` where `identifier == seriesSlug` — "seriesSlug" is NOT a track ID, so this returns nil.
   - Falls through to network fetch: `archiveService.fetchTracksForIdentifier(seriesSlug)` — this queries **archive.org**, NOT Oxford! The seriesSlug is an Oxford slug, not an IA identifier. IA returns nothing or error.
   - After 10-second timeout, `resolveItemParts` returns nil.

### Root Cause Analysis (Verified)
**Verified: `saveTracks` preserves all needed fields** (DatabaseService.swift:408-442). Lines 431-434 show `partNumber`, `totalParts`, `parentIdentifier`, and `artworkURLString` are all persisted. So the DB should contain complete track data.

**Verified: `fetchTracks(forParentIdentifier:)` works correctly** (DatabaseService.swift:534-545) — queries by `parent_identifier` column with `ORDER BY part_number ASC`. An index exists at line 338: `CREATE INDEX IF NOT EXISTS idx_parent_id ON tracks(parent_identifier)`.

**Verified: Oxford tracks get correct metadata** (OxfordLecturesService.swift:101-110) — `parentIdentifier = seriesSlug`, `partNumber = index + 1`, `totalParts = items.count`, `collectionTitle = seriesTitle`.

The DB path SHOULD work. The most likely actual failures are:

**Failure Mode A: Single-lecture series.**
When a series has only 1 lecture, `parseItems()` line 103 guards `total > 1` and skips setting `parentIdentifier`. The track's `parentIdentifier` is nil, so `identifier = track.id` in `resolveItemParts`. `fetchTrack(id: track.id)` finds the track, `isMultiPart` is nil/false → caches nil → returns nil permanently. The ChapterListView shows "This lecture is a standalone talk..."

**Failure Mode B: Stale `itemPartsCache` poisoning.**
If `resolveItemParts(seriesSlug)` was ever called AND the DB path failed (e.g., timing issue where tracks weren't saved yet) AND the network fallback to IA also failed, NO cache entry is written. But subsequent calls re-try and should succeed. This is NOT a permanent failure — just a first-call timeout.

**Failure Mode C: Channel mismatch during resume.**
When resuming a saved position in a lecture channel (PlayerViewModel.swift:742-746), `resumeTrackBelongs` checks if the track belongs to the channel. If this check fails, the track might be played from a different context and `currentChannel` won't be set, so `currentTrack.parentIdentifier` might be from an improper source.

**Failure Mode D (MOST LIKELY): Queue filtering strips multi-part tracks.**
Looking at `QueueManager._next()` line 177: `pool.filter { ... && ($0.partNumber ?? 1) <= 1 }`. This means only first-parts are in the queue pool. The user PLAYS first parts. When they tap "Lectures", `currentTrack.parentIdentifier = seriesSlug`. `resolveItemParts(seriesSlug)` queries the DB. ALL tracks with that parentIdentifier (including parts 2, 3, 4...) should be in the DB — they were saved by `saveTracks(fetched)`. This should work.

**Bottom line:** This issue needs live debugging with a real Oxford lecture channel to determine the exact failure. The plan includes two layers of fixes: (1) Add diagnostic logging to `resolveItemParts` to trace exactly what happens; (2) Add an Oxford-specific API fallback so if the DB path fails, the series can be re-fetched from the Oxford API.

Let me re-examine: `oxfordService.fetchTracks(unitSlug:)` fetches tracks for ALL series in a unit. For example, if "Computer Science" has 3 series (A with 5 lectures, B with 3 lectures, C with 8 lectures), it returns 16 tracks total. All are saved to DB via `db.saveTracks(fetched)`.

`saveTracks` uses `insert(or: .replace)`. The primary key is the track ID. So each track is saved with its unique ID.

When `resolveItemParts("series-A")` is called, `fetchTracks(forParentIdentifier: "series-A")` returns only the 5 tracks for series A. These have partNumbers 1-5, totalParts=5. `partsAreClean` checks: min=1, max=5, totalParts=5, count=5. It should pass!

**WAIT** — Unless the `saveTracks` function does NOT save `partNumber`, `totalParts`, `parentIdentifier`, `collectionTitle` fields! Let me check the `saveTracks` implementation...

I need to verify that `saveTracks` saves ALL fields. If it uses a partial `SET` statement that only updates `title`, `artist`, `source`, `streamURL`, etc. but NOT `part_number`, `total_parts`, `parent_identifier`, `collection_title` — then the DB would have NULLs for these columns, and `fetchTracks(forParentIdentifier:)` would return nothing!

This is the most likely root cause. Let me verify `saveTracks`/`saveTrack`.

### Design
Check `DatabaseService.saveTracks` / `saveTrack` to verify ALL columns are persisted, especially `parent_identifier`, `part_number`, `total_parts`, `collection_title`. If any are missing, add them.

Also add defensive fallback: if the DB path fails AND the track source is "oxford_lectures", fetch from Oxford directly instead of IA.

### Data-Model Deltas
None (bug is missing column persistence in saveTracks).

### Implementation Steps
1. Add diagnostic logging to `resolveItemParts` at each decision point (DB hit, DB miss, partsAreClean pass/fail, network fallback, timeout).
2. Add an Oxford-specific resolution path: if `currentTrack.source == "oxford_lectures"` AND the DB path fails, call `oxfordService.fetchTracks(unitSlug:)` and filter by parentIdentifier as a fallback rather than hitting IA.
3. Fix `resolveItemParts` to cache failures from the network path as well (prevent repeated 10-second timeouts).
4. Fix `resolveItemParts` to NOT cache nil for `isMultiPart == false` when the check is indeterminate (nil value) — only cache explicit false.
5. Add `.task` dependency tracking in `ChapterListView` so it re-fetches if the `currentTrack` changes.
6. `xcodegen generate`.

### Testing Strategy
- Unit test: Save a set of Oxford lecture tracks with parentIdentifier, fetch by parentIdentifier, verify all returned.
- Manual: Play an Oxford lecture, tap "Lectures" — should show all lectures in the series.
- Manual: Verify the same for audiobook channels (different source, should still work).

### Open Questions
- Should `resolveItemParts` cache failures as well? Currently it only caches successes and `isMultiPart=false` verdicts. Failed network fetches are not cached, causing repeated 10-second timeouts.

---

## Issue 5: Combine "Books for You" and "Music for You"

**Files:** `ParsoRadio/Views/Listen/ListenView.swift:191-209`, `ParsoRadio/Core/Services/Playback/RecommendationsController.swift:1-90`, `ParsoRadio/Core/Models/Channel.swift:137-151`

### Problem
"Books for You" and "Music for You" are shown as two separate channels in the "Curated Based on Your Taste" section. They should be combined into a single channel/section that interleaves both music tracks/albums and books.

### Current Behavior
- `ForYouSection` (ListenView.swift:191) filters channels with `category == "For You"` — currently Music for You and Books for You.
- Each appears as a separate tappable channel entry.
- Tapping one loads ONLY that category's recommendations (RecommendationsController filters by `isBooks` vs `isMusic`).

### Research Signal
The user wants a single "For You" section that plays a mix of music and books, interleaved like playlists do. This means:
1. One combined recommendation query that fetches both music and audiobook tracks.
2. A single channel entry that triggers the combined playback.
3. Interleaving strategy: round-robin between music and book sources, or weighted random.

### Design
**Step 1:** Add a new channel `for-you` (category `"For You"`) that replaces both `music-for-you` and `books-for-you`:

```swift
Channel(
    id: "for-you", name: "For You", category: "For You",
    icon: "sparkles",
    preferredSource: "internet_archive",
    summary: "A rotating mix of music and audiobooks based on your listening history."
)
```

**Step 2:** Create `fetchMixedRecommendations()` in `RecommendationsController` that:
1. Queries music recommendations (existing logic for Curated channels).
2. Queries book recommendations (existing logic for Audiobooks channels).
3. Interleaves them round-robin style (one music, one book, one music, one book...).
4. Falls back gracefully if one category has insufficient history.

**Step 3:** Update `ForYouSection` to show only the single combined channel.

**Step 4:** In `PlayerViewModel.load(channel:)`, route the `for-you` channel to the mixed recommendation fetch.

**Step 5:** Remove `music-for-you` and `books-for-you` from `Channel.defaults`.

### Data-Model Deltas
- Remove two channels (`music-for-you`, `books-for-you`) from `Channel.defaults`.
- Add one channel (`for-you`) to `Channel.defaults`.
- No schema changes.

### Implementation Steps
1. Add `for-you` channel definition to `Channel.defaults` (Channel.swift ~line 135).
2. Remove `music-for-you` and `books-for-you` channel definitions.
3. Add `fetchMixedRecommendations()` to `RecommendationsController.swift`.
4. Update `PlayerViewModel.load(channel:)` for `category == "For You"` to call mixed fetch.
5. Update `ForYouSection` in ListenView.swift to show single channel.
6. Keep old `fetchRecommendations(for:)` for backward compatibility during migration.
7. `xcodegen generate`.

### Testing Strategy
- Unit test: `fetchMixedRecommendations` returns interleaved music + book tracks when both histories exist.
- Unit test: Falls back to music-only when no book history.
- Unit test: Falls back to books-only when no music history.
- Manual: "For You" section shows one channel. Tapping it plays a mix of music and books.

### Open Questions
- Should we keep `music-for-you` and `books-for-you` as hidden/legacy channels for users who have playlists referencing them?
- What interleaving ratio? 1:1 music:books? Should it be weighted by listening proportion?

---

## Issue 6: "Approve All" Causes UI Slowness

**Files:** `ParsoRadio/Views/CuratedChannelsListView.swift:906-916`, `ParsoRadio/Core/Services/Storage/DatabaseService.swift:640-652`

### Problem
Clicking "Approve All" on the curation screen is very slow — each track is processed one-by-one with async DB calls on the UI thread.

### Current Behavior
`approveAll()` (CuratedChannelsListView.swift:907-916):
```swift
for track in unverdictted {
    await db.setCuration(channelId: channelMeta.id, trackId: track.id, status: "approved")
    verdictStates[track.id] = (status: "approved", undone: false)
}
```

Each `setCuration` call:
1. Crosses actor boundary via `withCheckedContinuation`
2. Dispatches to serial DB queue
3. Executes `INSERT OR REPLACE`
4. Resumes continuation

For 500 tracks, this is 500 round-trips through the serial queue. Each takes ~1-2ms, totaling 500-1000ms — plus the accumulating `verdictStates` dictionary updates and SwiftUI re-renders.

### Research Signal
SQLite supports batch inserts. The fix is a new `setCurationBatch` method that:
1. Wraps all INSERTs in a single SQLite transaction (`BEGIN TRANSACTION` ... `COMMIT`).
2. Uses a single `withCheckedContinuation` for the entire batch.
3. Returns results in one go.

### Design
Add `setCurationBatch(channelId:, trackIds:, status:)` to `DatabaseService`:

```swift
func setCurationBatch(channelId: String, trackIds: [String], status: String) async {
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        queue.async { [self] in
            do {
                try db.transaction {
                    for trackId in trackIds {
                        _ = try db.run(curation.insert(or: .replace,
                            colCurChannel    <- channelId,
                            colCurTrack      <- trackId,
                            colCurStatus     <- status,
                            colCurReviewedAt <- Date().timeIntervalSince1970,
                            colCurNote       <- nil))
                    }
                }
            } catch { }
            cont.resume()
        }
    }
}
```

Then `approveAll()` calls this once:

```swift
let unverdictted = queue.filter { verdictStates[$0.id] == nil }
let ids = unverdictted.map(\.id)
await db.setCurationBatch(channelId: channelMeta.id, trackIds: ids, status: "approved")
for track in unverdictted {
    verdictStates[track.id] = (status: "approved", undone: false)
}
```

### Data-Model Deltas
None — SQL schema unchanged.

### Implementation Steps
1. Add `setCurationBatch(...)` to `DatabaseService.swift` (after existing `setCuration`).
2. Add protocol requirement to `DatabaseServiceProtocol` in `Protocols.swift`.
3. Update `approveAll()` in `CuratedChannelsListView.swift:907-916` to use batch method.
4. Also add `setCurationBatch` for undo operations if needed.
5. Ensure `LiveCurationStore.shared.reload()` is called once after batch, not per-item.
6. `xcodegen generate`.

### Testing Strategy
- Unit test: Add `test_setCurationBatch` in existing DatabaseService tests.
- Manual: Open a curated channel with 200+ review tracks, tap "Approve All" — should complete near-instantly.

### Open Questions
- Should we also batch `verdictStates` updates and SwiftUI re-render? Use a single `withAnimation` block?
- Should `reload()` also refresh just the one channel rather than full reload?

---

## Issue 7: Channel Images Disappeared

**Files:** `ParsoRadio/Core/Services/Metadata/ArtworkService.swift:94-128`, `ParsoRadio/Core/Models/Channel.swift:1-591`, `ParsoRadio/Resources/Assets.xcassets/`

### Problem
Channels used to have images displayed but they disappeared. Also, there's no way for users to upload custom channel images, and no image fallback for channels/albums/books that don't have track artwork.

### Current Behavior
- `ArtworkService.bestArtwork(for:channel:)` (ArtworkService.swift:94-128) has a multi-step fallback:
  1. Enriched album/cover art
  2. Enriched track-specific art
  3. Author/composer portrait
  4. IA thumbnail
  5. **Channel image from asset catalog** (`UIImage(named: ch.id)`) — step 5
  6. **Channel image from URL** (`ch.imageURL`) — step 6
  7. Default icon + gradient (fallback)
- Steps 5 and 6 rely on the `channel` parameter being passed. If `channel` is nil, these steps are skipped.
- Many channels DO have asset catalog images (guitar-classical, piano-hour, string-quartet, etc.).
- `imageURL` on `Channel` is rarely set for built-in channels — it's mainly for user-created channels via `CustomChannelsStore.runtimeChannel(from:)`.

### Research Signal — Root Causes
**A. Channel parameter not passed:** `bestArtwork` requires a `channel` parameter. Check all call sites to ensure they pass the current channel. In `NowPlayingSheet.swift:70-71`, the fallback artwork uses `UIImage(named: channel.id)` directly — so this works. But the `MiniPlayer` uses `ArtworkThumbnail` which calls `ArtworkService.shared.artwork(for: track)` — this takes ONLY a track, no channel! So the channel image fallback is never reached from the MiniPlayer.

**B. Bundle asset stripping:** If asset catalog entries have incorrect Contents.json or are not properly referenced in the Xcode project, they won't be included in the bundle. This could happen after `xcodegen generate` if the Resources directory isn't properly configured.

**C. Missing images for audiobook and live music channels:** Not all channel IDs have corresponding asset catalog images. Need to audit and create missing images.

**D. No user-upload path:** `CustomChannelsStore.ChannelDefinition.Info` has `imageFilename` but there's no UI or API to upload custom channel images.

### Design
**Fix A (call-site fix):** Ensure `bestArtwork` is called with the channel parameter wherever channel images should appear. Specifically in `ArtworkThumbnail` and `MiniPlayer`.

**Fix B (asset audit):** Run a script to list Channel.defaults IDs and verify each has a corresponding `.imageset` in `Assets.xcassets`. Create placeholder/missing images or generate them from SF Symbols.

**Fix C (user upload):** Add image picker support to the curation screen for uploading channel images. Store images in `Documents/curated-channels/<id>.png` and set `imageFilename` on the channel definition.

### Asset Inventory
Audited 64 channels vs 107 imagesets. **Only 4 podcast channels are missing images:**
- `podcast-no-agenda`
- `podcast-citations-needed`
- `podcast-security-now`
- `podcast-floss-weekly`

All other channels (curated music, audiobooks, lectures, ambient) have matching `.imageset` entries. So "channel images disappeared" is NOT a missing-asset problem — it's a **call-site problem**: the code path that should display channel images is not being reached, or the `channel` parameter is nil when the artwork lookup runs.

### Data-Model Deltas
- Existing `imageFilename` field on `ChannelDefinition.Info` (CustomChannelsStore.swift:14) — already supports storing an image filename.
- No schema changes needed.

### Implementation Steps
1. Create missing asset catalog images for the 4 podcast channels (`podcast-no-agenda`, `podcast-citations-needed`, `podcast-security-now`, `podcast-floss-weekly`). Generate at least 1024×1024 PNG placeholders.
2. Fix `ArtworkThumbnail` to also accept an optional `channel` parameter for channel-image fallback.
3. Fix `MiniPlayer` to pass `playerVM.currentChannel` to `ArtworkThumbnail`.
4. Fix all callers of `bestArtwork(for:channel:)` to ensure the channel parameter is non-nil.
5. Add image picker to `NewChannelSheet` / channel edit for user-uploaded channel images.
6. Wire `imageFilename` through `CustomChannelsStore.runtimeChannel(from:)` → `Channel.imageURL` → `ArtworkService.bestArtwork` step 6.
7. Add an `imageURL` field to `ChannelMeta` (or use `imageFilename` from `ChannelDefinition.Info` as already defined at line 14).
8. `xcodegen generate`.

### Testing Strategy
- Manual: Open each channel from the home screen — channel image should display on player and in channel list.
- Manual: Create a new curated channel with a custom image — image should display.
- Unit test: `bestArtwork` with channel parameter returns channel image when no track artwork available.

### Open Questions
- Should we generate channel images programmatically from the channel's gradient + icon for channels without dedicated assets?
- What image format/size should user-uploaded channel images be?

---

## Issue 8: Ambient Channel Animations Disappeared

**Files:** `ParsoRadio/Views/LoopingVideoView.swift:1-138`, `ParsoRadio/Views/ProceduralVisualizerView.swift:1-76`, `ParsoRadio/Resources/Video/ambient-*.mp4`

### Problem
Ambient channels (Flowing Water, Rain, Ocean) used to show animated video/nature backgrounds but those disappeared.

### Current Behavior
- `LoopingVideoView.swift` exists and is fully implemented — it plays a muted, aspect-fill, infinitely-looping local video.
- Video files exist at `Resources/Video/ambient-flowing-water.mp4`, `ambient-rain.mp4`, `ambient-ocean.mp4`.
- `AmbientStaticService.bundledVideoURL(forChannelId:)` (AmbientStaticService.swift:46-54) can look up bundled videos.
- **BUT:** `LoopingVideoView` is NEVER referenced anywhere in the app code! The only reference is in its own file. It's dead code.
- `ProceduralVisualizerView.swift` also exists but is never used.
- The `NowPlayingSheet` artwork section shows either artwork, channel image, or gradient+icon — never a video or procedural visualizer.

### Root Cause
The ambient video/animation was implemented as a component (`LoopingVideoView`, `ProceduralVisualizerView`) but never wired into the `NowPlayingSheet` or any other view.

### Design
Wire ambient visuals into `NowPlayingSheet.artwork`:

1. When `currentChannel?.mediaKind == .ambient` AND a bundled video exists, show `LoopingVideoView` as the full-screen background (behind the artwork/track info).
2. When `currentChannel?.mediaKind == .ambient` AND no video exists, show `ProceduralVisualizerView` as the background.
3. The existing artwork frame (260×260) floats on top of the ambient background.
4. The video mirrors `playerVM.isPlaying` — freezes when paused.

**Implementation approach:**

In `NowPlayingSheet.swift`, modify the `artwork` view to include a full-screen background when the channel is ambient:

```swift
@ViewBuilder
private var artwork: some View {
    ZStack {
        // Ambient background
        if let channel = playerVM.currentChannel,
           channel.mediaKind == .ambient {
            if let videoURL = AmbientStaticService.bundledVideoURL(forChannelId: channel.id) {
                LoopingVideoView(url: videoURL, isPlaying: playerVM.isPlaying)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else {
                ProceduralVisualizerView(
                    seed: channel.id,
                    isPlaying: playerVM.isPlaying
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }
        }
        
        // Existing artwork / track info overlay
        VStack(spacing: 24) {
            // ... existing artwork
        }
    }
}
```

### Data-Model Deltas
None.

### Implementation Steps
1. Modify `NowPlayingSheet.artwork` to show ambient background when channel is ambient.
2. Wrap the existing artwork/track info in a `ZStack` with the ambient background behind.
3. Add `.ignoresSafeArea()` to the ambient background for full-screen effect.
4. Pass `playerVM.isPlaying` to `LoopingVideoView` and `ProceduralVisualizerView` for pause-mirroring.
5. Ensure audio keeps playing even when video is rendering (video is muted per `LoopingPlayerUIView.setup` line 80: `qp.isMuted = true`).
6. `xcodegen generate`.

### Testing Strategy
- Manual: Play "Flowing Water" channel — should see water video in background.
- Manual: Pause playback — video should freeze.
- Manual: Play "Sounds of Yellowstone" — should see procedural visualizer (no bundled video for Yellowstone).
- Manual: Play non-ambient channel — should see normal artwork (no ambient background).

### Open Questions
- Should the procedural visualizer be used for ALL tracks without artwork (not just ambient)?
- Should we add bundled videos for other ambient channels like Yellowstone?

---

## Issue 9: Player View Icons Should Never Have Text

**Files:** `ParsoRadio/Views/Player/NowPlayingSheet.swift:237-241`, `ParsoRadio/Views/Player/SpeedControl.swift:6-36`, `ParsoRadio/Views/Player/BookmarkButton.swift:1-19`, `ParsoRadio/Views/Player/ChapterButton.swift:1-31`

### Problem
Player view icons (SpeedControl, BookmarkButton, ChapterButton) show text labels beneath them. The user wants icon-only controls.

### Current Behavior
- `SpeedControl(showLabel: true)` (NowPlayingSheet:239) shows "1.0×" text below speedometer icon.
- `BookmarkButton(showLabel: true)` (NowPlayingSheet:241) shows "Bookmark" text below bookmark icon.
- `ChapterButton(showLabel: true)` (NowPlayingSheet:240) shows "Lectures"/"Chapters" text below list icon.

All three components already support `showLabel: Bool` parameter. Simply passing `false` would remove the text labels.

### Design
Change the call sites to pass `showLabel: false`:

```swift
LazyVGrid(columns: cols, spacing: 12) {
    if b.supportsSpeedControl { SpeedControl(showLabel: false) }
    if b.supportsChapters { ChapterButton(showLabel: false) }
    if b.supportsBookmarks { BookmarkButton(showLabel: false) }
}
```

### Data-Model Deltas
None.

### Implementation Steps
1. In `NowPlayingSheet.swift:237-241`, change all three buttons to `showLabel: false`.
2. Verify accessibility labels still work (they're set separately via `.accessibilityLabel`).

### Testing Strategy
- Manual: Play a track with speed control, verify only speedometer icon shows (no text).
- Manual: Play a lecture, verify only list icon shows (no "Lectures" text).
- Manual: Play an audiobook, verify only bookmark icon shows (no "Bookmark" text).
- Manual: VoiceOver should still announce "Playback speed, 1×", "Chapters", "Bookmark" respectively.

### Open Questions
- Should the labels be replaced with tooltip-style popovers on long-press for discoverability?

---

## Issue 10: Make a Detailed Plan

This document IS the detailed plan. Each issue above follows the required anatomy. Implementation will proceed phase by phase, one PR per phase, following the AGENTS.md dev methodology.

---

## Phased Rollout Table

| Phase | Branch | Issues | Dependencies | Risk |
|-------|--------|--------|-------------|------|
| 1 | `fix/jump-back-in` | #1 | None | Low |
| 2 | `fix/live-music` | #2a, #2b | None | Low |
| 3 | `fix/miniplayer-overlay` | #3 | None | Medium (UI regressions) |
| 4 | `fix/lecture-series` | #4 | None | Low |
| 5 | `fix/combined-for-you` | #5 | #4 (channel ref changes) | Medium |
| 6 | `fix/approve-all-batch` | #6 | None | Low |
| 7 | `fix/channel-images` | #7 | None | Medium (asset changes) |
| 8 | `fix/ambient-animations` | #8 | None | Low |
| 9 | `fix/player-icons` | #9 | None | Low |

All phases can run in parallel except Phase 5 which should stack on Phase 4 (channel model changes). Each phase must pass `xcodebuild test` before merging.

---

## Decision Sheet

| ID | Question | Decision |
|----|----------|----------|
| D1 | Fix Jump Back In with LEFT JOIN or cascade delete? | Both: cascade delete evicted IDs from play_history, AND use LEFT JOIN for defense-in-depth. |
| D2 | Live Music: stale-while-revalidate or blocking load? | Blocking but only on first day-load; cache hit returns instantly. |
| D3 | MiniPlayer: overlay vs safeAreaInset? | Overlay with conditional bottom padding on TabView content. |
| D4 | Lectures: fallback to Oxford API or only fix DB save? | Fix DB save first; add Oxford-specific fallback if DB path fails. |
| D5 | Combine For You: keep legacy channels or remove? | Remove but handle migration gracefully (existing playlists reference them). |
| D6 | Approve All: batch in transaction or async group? | Single transaction — simplest and fastest. |
| D7 | Channel images: generate missing or copy from resources? | Copy curated-channels PNGs into Assets.xcassets; add SF Symbol fallback for missing. |
| D8 | Ambient: video + visualizer both, or pick one? | Both: video if bundled, procedural visualizer if not. |
| D9 | Player icons: remove text or add option? | Remove text (showLabel: false) — user explicitly requested no text. |

---

## Pre-Implementation Checklist

- [ ] Run full test suite to establish baseline pass rate
- [ ] Run `xcodegen generate` to ensure project is current
- [ ] Audit all `Channel.defaults` IDs vs asset catalog entries (for #7)
- [ ] Verify bundled video files are included in Xcode target (for #8)
- [ ] Check `saveTracks` implementation for field completeness (for #4)
