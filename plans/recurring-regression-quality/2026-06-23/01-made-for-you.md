# 01 - Made For You Visibility And Update Backfill

## Problem

"Made for You" never appears for users, including existing users updating the app. The app has recommendation infrastructure, but the shelf can remain invisible before loading ever starts, and existing-user history is not converted into the taste-profile data the shelf expects.

## Current Behavior

Physical files involved:

- `ParsoRadio/Views/Listen/ListenView.swift`
- `ParsoRadio/Views/Listen/MadeForYouSection.swift`
- `ParsoRadio/Core/Services/Playback/RecommendationsController.swift`
- `ParsoRadio/Core/Services/Storage/TasteProfileStore.swift`
- `ParsoRadio/Core/Services/Storage/DatabaseService.swift`
- `ParsoRadio/Views/OnboardingTasteView.swift`
- `ParsoRadio/Core/Tests/MadeForYouVisibilityTests.swift`
- `ParsoRadio/Core/Tests/RecommendationsControllerTests.swift`
- `ParsoRadio/Core/Tests/TasteProfileStoreTests.swift`

Current observed behavior:

- `ListenView` places `MadeForYouSection()` near the top of the Listen list.
- `MadeForYouSection` starts with `showSection = false`.
- The root `body` is `if showSection { Section { ... }.task { await loadIfNeeded() } }`.
- Because the root branch is not mounted at first render, the `.task` that flips `showSection = true` is not attached. This creates a self-blocking lifecycle.
- `hasCompletedOnboarding` is read in `MadeForYouSection` but is not used to decide loading or presentation.
- Cold start fallback only runs when `hasProfile == false`. If a user has stale, sparse, or unusable profile terms, failed recommendations can still leave the shelf empty.
- Existing users may have rows in `track_play_history` and `tracks`, but no automatic migration into `taste_profile_terms`, `taste_seen_identifiers`, or `reco_surfaced`.
- Existing tests prove taste-store primitives work, but they do not instantiate the real shelf lifecycle or prove the section becomes visible.

## Research Signal

- Personalized shelves should be stable, low-effort destinations. Spotify's Discover Weekly is useful because it is predictably present and refreshed, not because the user has to discover whether it exists on a given launch.
- SwiftUI view tasks only run for mounted views. A task attached under an initially false branch cannot be used as the mechanism that makes the branch visible.
- The app already stores durable listening history in `DatabaseService.recordPlayed(channelId:trackId:)`; the profile layer should consume that for upgraders.
- Tests should focus on the production shelf state machine and database backfill path, following the Test Pyramid principle that a high-level failure should be reproduced by a focused lower-level test.

## Design

Replace the view-local visibility flags with a small production state machine.

```
ListenView
  |
  +-- MadeForYouSection  (always mounted)
        |
        +-- MadeForYouShelfStore.load(reason:)
              |
              +-- ensureBackfillIfNeeded()
              |     track_play_history JOIN tracks -> TasteProfileStore
              |
              +-- RecommendationsController.fetchMixedRecommendations()
              |
              +-- coldStartProvider.fetchPicks()
              |
              +-- state:
                    idle
                    loading
                    loaded(personalized, [Track])
                    loaded(coldStart, [Track])
                    empty(message)
                    failed(message, retryable)
```

UI contract:

```
Section header: Made for You

loading:
  [spinner] Finding fresh picks...

loaded:
  [track card] [track card] [track card] ...
  Fresh picks from your taste / Starter picks while Lorewave learns

empty/failed:
  Could not build your shelf right now.
  [Retry]
```

The section must be visible after the onboarding sheet has been dismissed, including when onboarding was skipped. It remains visible even if it is in `loading`, `empty`, or `failed`. Do not gate the root section on `tracks.isEmpty`.

## Data-Model Deltas

No destructive schema changes.

Required additive/runtime state:

- Add a versioned backfill marker such as `UserDefaults.standard.integer(forKey: "tasteProfileBackfillVersion")`.
- Reuse existing tables:
  - `track_play_history`
  - `tracks`
  - `taste_profile_terms`
  - `taste_seen_identifiers`
  - `reco_surfaced`

Required additive DB methods/tables:

- `DatabaseService.fetchRecentlyPlayedTracksForTasteBackfill(limit:) -> [Track]`
  - Must explicitly join `track_play_history` to `tracks`.
  - Must order by `played_at DESC`.
  - Must cap rows, for example 200.

- Add a small daily shelf cache:
  - `made_for_you_daily_cache(day TEXT, position INTEGER, track_id TEXT, source TEXT, created_at REAL)`
  - `day` uses full `yyyy-MM-dd`.
  - Track data remains in `tracks`; the cache only stores ordered track ids and source labels.
  - Cache is additive and can be rebuilt if missing.

## Implementation Steps

1. Create `MadeForYouShelfStore` under `ParsoRadio/Core/Services/Playback/` or `ParsoRadio/ViewModels/` as `@MainActor ObservableObject`.
   - Inputs: `DatabaseService`, `InternetArchiveService`, `TasteProfileStore`.
   - Published state: `MadeForYouShelfState`.
   - Public methods: `loadIfNeeded()`, `refresh()`, `invalidateForHistoryChange(version:)`.

2. Move `MadeForYouSection` lifecycle out of `if showSection`.
   - Always return a `Section`.
   - Attach `.task(id: playerVM.playHistoryVersion)` to the mounted section or a stable wrapper.
   - Remove `showSection`; visibility should be derived from state.

3. Add existing-user backfill.
   - In `MadeForYouShelfStore.loadIfNeeded()`, call `ensureTasteBackfillIfNeeded()`.
   - If `taste_profile_terms` is empty and recent play history exists, seed terms using `TasteProfileStore.seedFromTrack(track, channel: nil)` and mark seen identifiers.
   - Also mark a backfill version after success so this does not run on every launch.
   - If the backfill fails midway, do not mark success.

4. Make cold-start fallback resilient.
   - Run cold-start picks when recommendations return `nil`, throw, or produce fewer than `RecommendationConstants.minShelf`, regardless of `hasProfile`.
   - Label fallback state as starter/cold-start in the state enum so UI copy remains honest.
   - Keep the fallback query list in one testable provider rather than inside a private view method.
   - Cold-start content must include both music and audiobooks, with an explicit `MediaKind` for each tapped item.
   - Cold-start providers must use the global MP3-only policy and reject every non-MP3 result.

5. Keep playback context explicit on taps.
   - When tapping a Made For You track, call a VM method that supplies `MediaKind` based on the track or shelf bucket.
   - Do not use `playRecentTrack` as a generic "play any recommendation" path if it clears context without media kind.

6. Persist the daily shelf.
   - Save the selected track ids into `made_for_you_daily_cache` after a successful personalized or cold-start load.
   - On same-day reload, render cached tracks first, then refresh in the background.
   - If cached tracks are missing from `tracks`, rebuild the cache.

7. Remove misleading unused state.
   - Delete `@AppStorage("hasCompletedOnboarding")` from `MadeForYouSection` unless the new state machine genuinely uses it.

8. Add error logging.
   - Log recommendation failures with a short reason, but keep UI copy user-safe.

## Testing Strategy

Add focused tests before changing the view:

- `MadeForYouShelfStoreTests`
  - Empty DB -> state becomes `.loaded(.coldStart, tracks)` when cold-start provider returns tracks.
  - Existing `track_play_history` + `tracks` + empty `taste_profile_terms` -> backfill creates profile terms and seen identifiers.
  - Recommendation failure with non-empty profile -> cold-start fallback still surfaces tracks.
  - Recommendation and fallback failure -> state is `.empty` or `.failed`, not hidden.

- `MadeForYouSectionLifecycleTests`
  - Verify the section's initial state is mountable and can enter `.loading` without relying on a prior `showSection`.
  - If UI inspection is unavailable, add a pure state test and a source-guard test that rejects the root pattern `if showSection { Section`.

- `RecommendationsControllerTests`
  - Use a fake archive service or extracted protocol so the test can deterministically return recommendations and fallback candidates.

- `DatabaseServiceTests`
  - Verify backfill fetch joins `track_play_history` to `tracks`, excludes orphaned rows, orders newest first, and caps row count.
  - Verify daily shelf cache stores full-date keys, preserves order, joins to existing tracks, and rebuilds when tracks are missing.

Targeted manual verification:

1. Fresh install, skip onboarding: Listen tab shows "Made for You" loading then starter picks or a retry state.
2. Fresh install, complete onboarding: Listen tab shows personalized picks.
3. Simulated upgrader with play history but empty profile: first launch backfills and shows the shelf.
4. Offline launch: shelf remains visible with cached/starter/error state, not missing.

## Settled Decisions

- Show Made For You after the onboarding sheet is dismissed, including when the user skipped onboarding.
- Cold-start content includes both music and audiobooks.
- Add the daily shelf cache in Phase 1.
- Failed recommendation fetches show a visible retry affordance and remain refreshable through pull-to-refresh.
