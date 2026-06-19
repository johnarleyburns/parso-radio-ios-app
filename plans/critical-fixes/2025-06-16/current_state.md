# Current State — June 16, 2025

## Branch: `main` (HEAD: `461664a`)

> fix: update tests for channel count, shuffle behavior, ambient bookmarks; replace app icon

---

## Project Baseline

| Item | Status |
|------|--------|
| `xcodegen generate` last run | Unknown — needs re-run before building |
| Unit tests pass? | Unknown — needs verification |
| Integration tests pass? | Unknown — needs verification |
| Xcode project up to date | Stale — new files from plan not yet added |

---

## 10 Critical Issues — Status

| # | Issue | Status | Root Cause Found? | Files Affected |
|---|-------|--------|-------------------|----------------|
| 1 | Jump Back In never displays | **Not started** | Yes — `INNER JOIN` orphaning after `evictOldTracks` | `DatabaseService.swift:602-626,1212-1243`, `ListenView.swift:304-341` |
| 2a | Live Music wrong size at startup | **Not started** | Yes — inconsistent loading/loaded height | `ListenView.swift:221-287` |
| 2b | Live Music reloading on tab switch | **Not started** | Yes — `.task` fires on every appearance with `isLoading = true` | `ListenView.swift:282-287`, new file needed: `LiveMusicOnThisDayStore.swift` |
| 3 | MiniPlayer overlays tab bar | **Not started** | Yes — `.safeAreaInset` position on TabView | `RootTabView.swift:17`, `MiniPlayer.swift:1-59` |
| 4 | Lectures button can't find series | **Not started** | Partial — DB fields verified correct; needs live debug logging | `WholeItemController.swift:18-69`, `BookmarkController.swift:34-38` |
| 5 | Combine Books + Music For You | **Not started** | N/A — design change | `Channel.swift:137-151`, `ListenView.swift:191-209`, `RecommendationsController.swift:1-90` |
| 6 | Approve All causes UI slowness | **Not started** | Yes — one-by-one async DB calls | `CuratedChannelsListView.swift:907-916`, `DatabaseService.swift:640-652` |
| 7 | Channel images disappeared | **Not started** | Yes — only 4 podcast channels missing assets; real issue is call-site not passing channel | `ArtworkThumbnail.swift`, `MiniPlayer.swift`, `NowPlayingSheet.swift:70-71` |
| 8 | Ambient animations disappeared | **Not started** | Yes — `LoopingVideoView`/`ProceduralVisualizerView` exist but are dead code (never referenced) | `NowPlayingSheet.swift:61-112`, `LoopingVideoView.swift` |
| 9 | Player view icons show text | **Not started** | Yes — `showLabel: true` default on all 3 controls | `NowPlayingSheet.swift:237-241` |

---

## Assets Verified

- **Channel images:** 64 channels → 60 have matching `.imageset` entries in `Assets.xcassets`. 4 missing: `podcast-no-agenda`, `podcast-citations-needed`, `podcast-security-now`, `podcast-floss-weekly`.
- **Ambient videos:** `Resources/Video/ambient-flowing-water.mp4`, `ambient-rain.mp4`, `ambient-ocean.mp4` exist on disk. Not wired into any view.
- **DB schema:** `tracks` table includes `part_number`, `total_parts`, `parent_identifier`, `collection_title` columns. Index on `parent_identifier` exists. `saveTracks` persists all fields.

---

## Implementation Phases (as planned)

| Phase | Branch Name | Issues | Risk |
|-------|-------------|--------|------|
| 1 | `fix/jump-back-in` | #1 | Low |
| 2 | `fix/live-music` | #2a, #2b | Low |
| 3 | `fix/miniplayer-overlay` | #3 | Medium |
| 4 | `fix/lecture-series` | #4 | Medium |
| 5 | `fix/combined-for-you` | #5 | Medium |
| 6 | `fix/approve-all-batch` | #6 | Low |
| 7 | `fix/channel-images` | #7 | Medium |
| 8 | `fix/ambient-animations` | #8 | Low |
| 9 | `fix/player-icons` | #9 | Low |

Phases 1-4 and 6-9 are independent. Phase 5 should stack on Phase 4 (both touch channel model).

---

## Pre-Implementation Verification Needed

- [ ] Run `xcodegen generate` to regenerate Xcode project
- [ ] Run full unit test suite: `xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ParsoMusicTests`
- [ ] Verify no test regressions on current `main`
- [ ] Create missing asset images for 4 podcast channels (not blocking — can do in Phase 7)

---

## Open Decisions

| ID | Question | Status |
|----|----------|--------|
| D1 | LEFT JOIN vs cascade delete for Jump Back In? | Decided: **both** for defense-in-depth |
| D2 | Stale-while-revalidate for Live Music? | Decided: **blocking first load, instant cache hit after** |
| D3 | Overlay vs safeAreaInset for MiniPlayer? | Decided: **overlay with conditional bottom padding** |
| D4 | Oxford fallback in resolveItemParts? | Decided: **fix DB path first, add Oxford-specific fallback as safety net** |
| D5 | Keep legacy For You channels? | Decided: **remove, handle migration** |
| D6 | Batch SQL in transaction or async group? | Decided: **single transaction** |
| D7 | Generate placeholder images or SF Symbol fallback? | Decided: **create PNG placeholders for 4 missing channels + SF Symbol for user-created channels** |
| D8 | Video or procedural visualizer for ambient? | Decided: **video if bundled, procedural if not** |
| D9 | Remove text or add toggle for player icons? | Decided: **remove text (showLabel: false)** |
