# Current State

Last updated: 2026-06-25 (all phases implemented + verified)

| Phase | Status |
|------|--------|
| 0 — foundation (media_kind, fetchRecentlyPlayedWorks, stable album key, UITest seam) | done |
| 1 — chapter dedup (fetch-layer + dedupeParts + partsAreClean) | done |
| 2 — surface kind (persisted-kind contexts, playSearchResult, source guards) | done |
| 3 — jump back in works (work cards, resumeWork, single fullScreenCover) | done |
| 4 — search favorites (ItemDetailView favorite + search row swipe) | done |

## Verification results
- `ParsoMusicTests`: 742 tests, 0 failures.
- `ParsoMusicUITests` (new): `JumpBackInBookUITests` (4), `ChapterDuplicationUITests` (1), `FavoritesInSearchUITests` (1) — all pass.

## Notable implementation deltas vs. plan
- Added `collection_title` to the tracks table (additive) so a chapter carries its book title into the "Jump back in" work card (it was previously transient and lost on DB round-trip).
- Consolidated the two stacked `.fullScreenCover` modifiers in `ListenView` into a single enum-driven (`ListenPresentation`) cover attached to the `NavigationStack` — the stacked covers silently failed to present, so Jump Back In taps did nothing. `FeaturedTodaySection` now takes an `onSelect` closure instead of a binding.
- `JumpBackInCard` is a single combined accessibility element (image clipped + hidden) so XCUITest can tap it.
- UITest seam (`UITestSupport`, `-uiTestSeed`): seeds a tripled "Gallipoli" book + a music album + history + a saved book position; suppresses the onboarding cover and resets Kids Mode / seeded favorites so runs are deterministic.

## Known follow-ups (out of scope)
- `DatabaseService.wipeAllData()` does NOT clear the `favorites` table (Settings → "Clear All Data" leaves favorites). Pre-existing; the UI-test seed works around it by deleting the specific ids.
