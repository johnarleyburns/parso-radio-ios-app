# June 5 Implementation Plan

## PHASE 1: Curation Bug Fixes (COMPLETED)
### Bug 1: Track failure doesn't advance to next track
- PlayerViewModel.swift, CuratedChannelsListView.swift, CuratorModeView.swift
### Bug 2: Undo reloads entire screen  
- CuratedChannelsListView.swift
### Bug 3: Return from curation plays wrong track
- PlayerViewModel.swift

## PHASE 2: Age Assurance (COMPLETED)
- AgeAssuranceService.swift, AgeGateView.swift, ParsoRadioApp.swift, KidsModeController.swift
- ParsoMusic.entitlements with com.apple.developer.declared-age-range

## PHASE 3: Supporter Badges (COMPLETED)
- ContributionStore.swift (SubscriptionTier enum + activeSubscriptionProductID)
- iPodView.swift (badge overlay bottom-right), SettingsView.swift (toggle)

## PHASE 4: Privacy Policy (COMPLETED)
- lorewave-privacy.html, FOR_APPSTORE_REVIEWERS.md, AboutView.swift link update

---

# Expanded Curation Plan — June 6

## BUG A: Curated channel list shows stale count (e.g., "3" instead of dozens)

### Root cause
`CuratedChannelsListView:88` reads `store.approvedTracks(for: meta.id).count` from the per-channel **JSON file**.
But verdict button (`verdict()` at line 714) only writes to the **database**, never updates the JSON.
The JSON freezes at its initial bundled state. Only Search-Add verdicts write to JSON.
DB, LiveCurationStore, and in-editor counts are all correct — only the channel list display is stale.

### Fix
Change line 88 to read from the in-memory DB-backed cache:
```swift
// OLD:
let approvedCount = store.approvedTracks(for: meta.id).count
// NEW:
let approvedCount = LiveCurationStore.shared.pool(for: meta.id).count
```
`LiveCurationStore` is refreshed after every `verdict()` and `undoVerdict()` via `.reload(from: db)`.
1 line. No new dependencies.

---

## BUG B: Review counts mismatch during active curation

### Root cause (two sub-issues)

**Sub-issue 1 — Undo on filter tabs:** In the undo fix (Bug 2), `undoVerdict()` was changed from `await reload()` to `counts = await db.curationCounts(...)`. This correctly updates counts but leaves the `queue` stale. When viewing the "Approved" or "Rejected" filter tab and undoing a verdict, the undone track stays visible in the list because `queue` wasn't reloaded from the filter-mode source. Count says 2, but 3 rows are visible.

**Sub-issue 2 — Orphaned curation rows:** `curationCounts()` (DatabaseService.swift:495) counts raw curation-table rows with NO JOIN to `tracks`. If tracks were evicted by `evictOldTracks()` (which preserves curation rows), orphaned curation rows inflate the count. The badge shows "3 items left" but the queue is empty (because `reviewSetTracks()`/`fetchApprovedTracks()` JOIN the tracks table and find nothing).

### Fix 1 — Undo on filter tabs
In `undoVerdict()` (line 734), after counts update:
```swift
if filterMode != .review { await reload() }
```
When on the Review tab, the undone track naturally stays visible (it's now "review" again).
On Approved/Rejected tabs, the track must disappear — so reload the filter-mode queue.

### Fix 2 — Orphan curation rows
Change `curationCounts()` to JOIN the `tracks` table:
```
-- OLD: SELECT COUNT(*) FROM curation WHERE channel_id=? AND status=?
-- NEW: LEFT JOIN tracks so orphaned rows aren't counted
```

---

## BUG C: Clicking search result doesn't show track info

### Root cause
`SearchView:222` sets `selectedResult = group` which triggers a `confirmationDialog` (Play/Add to Playlist).
No track info sheet exists at all in SearchView.
Compare to `CuratorChannelEditView:636` where tapping the title opens a track info sheet.

### Fix — SearchView
1. Add `@State private var infoGroup: SearchViewModel.ResultGroup?`
2. Change line 222 from `.onTapGesture { selectedResult = group }` to `.onTapGesture { infoGroup = group }`
3. Add `.sheet(item: $infoGroup)` showing track info (title, creator, duration, collection, id, kind badge)
4. Move the ellipsis button (line 210) to continue triggering `selectedResult = group` for the actions dialog
5. Show Track/Album/Book kind label in the info sheet

---

## BUG D: Search results — no failure warning icon/toast

### Root cause
`SearchView` has no `failedTrackIds`, `flashTrackId` and no `.onChange(of: playerVM.errorMessage)` observer.
`PlayerViewModel` sets `errorMessage` on failure, but `SearchView` never observes it.

### Fix — SearchView
1. Add `@State private var failedTrackIds: Set<String> = []` and `@State private var flashTrackId: String?`
2. Add `.onChange(of: playerVM.errorMessage)` (same pattern as `CuratedChannelsListView:570-590`)
3. In each result row, show `exclamationmark.triangle.fill` icon (yellow, with flash)
4. After flash, clear the indicator (there's no "next" track in search results)

---

## BUG E: Curator search list — no failure warning + no track info

### Root cause
`CuratorSearchAddView` (CuratorModeView:502-559) has no failedTrackIds, flashTrackId, infoTrack and no `.onChange(of: playerVM.errorMessage)`.

### Fix — CuratorSearchAddView
1. Add `@State` variables: `failedTrackIds`, `flashTrackId`, `infoGroup`
2. Add `.onChange(of: playerVM.errorMessage)` with failure-handling pattern
3. Add `.onTapGesture { infoGroup = group }` to the track title in `resultRow()`
4. Add `.sheet(item: $infoGroup)` for a track info sheet
5. Show failure warning icon in result rows

---

## BUG F: After accept/reject in curator search list, plays random track

### Root cause
`CuratorSearchAddView.directVerdict()` (line 652) calls `playerVM.stopAudition()` when the verdicted track is playing.
But `stopAudition()` restores the pre-audition channel (from our Bug 3 fix). The user expects silence after verdict.

Also applies to: curator review queue exhaustion — when all items reviewed, `stopAudition()` restores old channel instead of silence.

### Fix
Add `stopAuditionWithoutRestore()` to `PlayerViewModel` that discards `preAuditionState`:
```swift
func stopAuditionWithoutRestore() {
    guard currentChannel == nil, currentPlaylist == nil else { return }
    stallWatchdog?.cancel(); stallWatchdog = nil
    audioPlayer.skip()
    currentTrack = nil; trackDuration = nil
    isPlaying = false; isLoading = false; loadingMessage = nil
    failedAuditionTrackId = nil; errorMessage = nil
    playbackContextToken &+= 1
    isAuditioning = false
    preAuditionState = nil   // discard, don't restore
}
```
Use `stopAuditionWithoutRestore()` in:
- `CuratorSearchAddView.directVerdict()` (line 652)
- `CuratorChannelEditView.verdict()` when queue exhausted (line 730)
- `CuratorReviewView.verdict()` when queue exhausted (line 425)

---

## BUG G: Album vs Track detection — visual indicator + full-album verdict

### Root cause
Classification logic exists in `SearchViewModel.classify()` (tracks vs albums vs books based on audioCount + IA collection name).
But:
1. The review queue only operates on individual tracks — approving an album requires approving each track separately
2. There's no indicator in the review queue showing whether a track is part of a multi-part album

### Fix
1. In curator review rows, detect multi-part tracks via `track.isMultiPart` / `track.parentIdentifier`
2. Show "Album (Part X of N)" or "Book (Chapter X of N)" label in the review row
3. Add these buttons to the track info sheet:
   - "Add track to [other curated channel]" (lists other curated channels)
   - "Add entire album to review queue" (fetches all parts, adds to review)
   - "Add entire album to new curated channel" (creates channel + adds all parts)
4. For SearchView result rows, already show Track/Album/Book badge — extend to show audio count

---

## IMPLEMENTATION ORDER

| # | Bug ID | Description | Files | Est. Lines |
|---|--------|-------------|-------|------------|
| 1 | B-fix2 | Fix `curationCounts()` JOIN orphans | `DatabaseService.swift` | ~5 |
| 2 | A | Channel list count: JSON → LiveCurationStore | `CuratedChannelsListView.swift:88` | 1 |
| 3 | B-fix1 | Undo on filter tabs: reload non-review | `CuratedChannelsListView.swift:748` | 3 |
| 4 | F | Add `stopAuditionWithoutRestore()` | `PlayerViewModel.swift` | ~15 |
| 5 | F | Use it in curator views | 3 curator view files | ~6 |
| 6 | C | Add track info sheet to SearchView | `SearchView.swift` | ~40 |
| 7 | D | Add failure indicators to SearchView | `SearchView.swift` | ~30 |
| 8 | E | Add failure indicators + info to CuratorSearchAddView | `CuratorModeView.swift` | ~50 |
| 9 | G | Album detection label in review rows | 2 curator views | ~20 |
| 10 | G | Album verdict buttons in track info sheet | 2 curator views | ~40 |
| 11 | — | Update/add tests | `CurationTests.swift` + new | ~60 |

**Total estimated: ~270 lines across ~8 files.**
