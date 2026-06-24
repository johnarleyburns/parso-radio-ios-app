# Recurring Regression Quality Plan

## Objective

This is a plan-only handoff for five recurring problems:

1. "Made for You" never appears, including for users updating from an older app.
2. "Live Music on This Day" can show unplayable or under-enriched items with no clear error.
3. Elapsed time, remaining time, work-level time left, and scrubber control keep being removed or bypassed.
4. Direct launch paths, especially "A Book Curated For You", can open the wrong player surface.
5. Agents keep claiming incomplete work is implemented, and existing tests are not stopping regressions.

No application code should be changed as part of this planning phase. The implementation should be done in small PRs using the settled decisions in `decisions.md`.

## Raw Notes From Codebase Research

- `ParsoRadio/Views/Listen/MadeForYouSection.swift` gates the entire body behind `if showSection`. Because `showSection` starts as `false`, the `.task(id: playerVM.playHistoryVersion)` attached inside that branch does not mount, so `loadIfNeeded()` has no reliable path to run. This is the primary reason the shelf can never appear.
- `MadeForYouSection` also only treats users with no taste profile as cold-start users. Existing upgraders can have `track_play_history` but no `taste_profile_terms`, and no migration/backfill creates terms from prior play history.
- `ParsoRadio/Core/Services/API/LiveMusicOnThisDayService.swift` chooses from search results before validating playable files. Its date mismatch branch caches and returns the original, unenriched pick, and its final fallback returns `pool.first` even if every enriched candidate failed.
- `ParsoRadio/Views/Listen/LiveMusicDetailView.swift` loads tracks through `playerVM.resolveItemParts(identifier:)`, which intentionally returns `nil` for single-file items. That is wrong for live recordings where a single playable file is acceptable.
- `ParsoRadio/Views/Player/NowPlayingSheet.swift` chooses controls using `playerVM.currentChannel?.mediaKind ?? .music`. Direct contexts and playlist contexts set `currentChannel = nil`, so book content can land on the music surface.
- `ParsoRadio/Core/Services/Playback/WholeItemController.swift`, `RecentlyPlayedController.swift`, and `PlaylistPlaybackController.swift` create channel-less playback contexts without a persistent `MediaKind` or surface contract.
- `ScrubRow` and `ScrubBar` still exist in `ParsoRadio/Views/Player/PlayerControlBits.swift` and `ParsoRadio/Views/Player/ScrubBar.swift`. The repeated regression is that the active route bypasses `SpokenControls`, not that the UI elements are impossible to render.
- Several tests under `ParsoRadio/Core/Tests/NowPlayingSheetTests.swift` and `PlayerSurfaceIntegrationTests.swift` assert booleans constructed in the test rather than exercising the production code path that chooses a surface. They document intent but do not fail when production drifts.
- Audio file selection is too permissive for the reliability target. The settled requirement is MP3-only across all playback paths.

## Research Signal

- Internet Archive's Metadata Read API returns a full item record at `https://archive.org/metadata/{identifier}`, including a `files` array and `metadata` object. The docs also state many top-level fields are optional, so Lorewave must validate required fields itself instead of assuming search docs are complete: https://archive.org/developers/md-read.html
- Internet Archive's metadata schema emphasizes that item metadata is what makes items findable and useful, and notes item-level metadata and file-level metadata are separate records. Live Music must therefore treat item metadata and playable file metadata as one candidate contract: https://archive.org/developers/metadata-schema/index.html
- Spotify's personalized playlist pattern shows why "Made for You" should be a stable, visible listening destination with a fallback, not a hidden shelf that appears only when every recommendation dependency succeeds. Public reporting on Discover Weekly frames it as a low-effort, regularly refreshed playlist experience: https://time.com/4131520/spotify-discover-weekly-playlists/
- Martin Fowler's Test Pyramid argues for many more focused low-level tests than broad GUI tests, and for reproducing a high-level failure with a lower-level test before fixing it: https://martinfowler.com/bliki/TestPyramid.html
- Google Testing Blog highlights the needed feedback loop properties for quality gates: fast, reliable, and failure-isolating tests. This app's current regression tests need to move in that direction: https://testing.googleblog.com/2015/04/just-say-no-to-more-end-to-end-tests.html

## Cross-Cutting Design Principles

1. Use explicit production contracts, not view-local inference. Player surfaces should be selected from a typed playback context, and tests should exercise that same resolver.
2. Validate before display. Live Music should never publish an entry until title/date/playable-track contracts have passed or the UI is intentionally in an error/empty state.
3. Mount feature sections before loading. A feature cannot load from a `.task` attached to a branch that is initially invisible.
4. Existing users are first-class. Any new profile/cache table needs an update path from existing durable data, not only new forward writes.
5. Tests must fail on the production failure mode. Do not add tests that only restate desired booleans or duplicate view logic in the test file.
6. Use MP3 only. Reject Ogg, FLAC, M4A, AAC, Opus, WAV, SHN, video containers, metadata-only files, and every other non-MP3 format before playback.
7. Every finite non-ambient surface keeps elapsed time, remaining time, and a scrubber. Books and lectures also keep work-level time left.

## Handoff Map

```
plans/recurring-regression-quality/2026-06-23/
  00-overview.md
  01-made-for-you.md
  02-live-music-on-this-day.md
  03-player-surfaces-and-time-controls.md
  04-agent-process-quality-gates.md
  05-rollout-schema-verification.md
  current_state.md
  decisions.md
```

## Recommended Sequence

1. Fix the production surface/lifecycle contracts first: Made For You visibility and explicit player surface selection.
2. Fix Live Music validation and user-visible error states.
3. Replace weak tests with production contract tests and update process documentation.
4. Run the local unit test gate after each phase, then run targeted UI/integration tests for the user-facing surfaces.

## Non-Goals

- Do not redesign the Listen tab visual hierarchy beyond the sections named here.
- Do not remove existing player controls.
- Do not perform destructive database migrations.
- Do not push directly to `main` from a coding-agent branch without local verification.
