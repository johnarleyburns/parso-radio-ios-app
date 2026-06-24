# 05 - Rollout, Schema, And Verification

## Problem

The fixes touch separate but related systems. They need to land in a sequence that keeps the app buildable and prevents partial fixes from masking each other.

## Current Behavior

Physical files involved across all phases:

- `ParsoRadio/Views/Listen/ListenView.swift`
- `ParsoRadio/Views/Listen/MadeForYouSection.swift`
- `ParsoRadio/Views/Listen/LiveMusicDetailView.swift`
- `ParsoRadio/Core/Models/LiveMusicEntry.swift`
- `ParsoRadio/Core/Models/MediaKind.swift`
- `ParsoRadio/Core/Models/MediaKind+Resolve.swift`
- `ParsoRadio/Core/Services/API/LiveMusicOnThisDayService.swift`
- `ParsoRadio/Core/Services/API/LiveMusicOnThisDayStore.swift`
- `ParsoRadio/Core/Services/API/InternetArchiveService.swift`
- `ParsoRadio/Core/Services/Playback/RecommendationsController.swift`
- `ParsoRadio/Core/Services/Playback/WholeItemController.swift`
- `ParsoRadio/Core/Services/Playback/PlaylistPlaybackController.swift`
- `ParsoRadio/Core/Services/Playback/RecentlyPlayedController.swift`
- `ParsoRadio/Core/Services/Storage/TasteProfileStore.swift`
- `ParsoRadio/Core/Services/Storage/DatabaseService.swift`
- `ParsoRadio/ViewModels/PlayerViewModel.swift`
- `ParsoRadio/Views/Player/NowPlayingSheet.swift`
- `ParsoRadio/Views/Player/PlayerControlBits.swift`
- `ParsoRadio/Views/Player/ScrubBar.swift`
- `ParsoRadio/Views/Player/Controls/SpokenControls.swift`
- `ParsoRadio/Core/Tests/`
- `ParsoRadio/Integration/Tests/`
- `ParsoRadio/UITests/`
- `AGENTS.md`
- `.github/workflows/ios.yml`

Current risks:

- Fixing Live Music playability without explicit playback context can still show the wrong player surface.
- Fixing player surfaces without replacing weak tests can regress again.
- Fixing Made For You recommendations without fixing section lifecycle can still keep the shelf invisible.
- Adding tests after implementation can reproduce the agent sloppiness pattern; write failing contract tests first.
- Leaving non-MP3 formats in any selector can reintroduce AVPlayer reliability issues.

## Research Signal

- The most reliable test strategy here is a layered one: pure contract tests for state/resolution/audio-format policy, service tests with mocked IA metadata, integration tests for real IA behavior, and a few UI smoke tests for accessibility-visible controls.
- Required schema changes are additive only: Made For You daily cache and playlist media-kind hints. Session media kind uses `UserDefaults`.

## Design

Phased rollout:

```
Phase 0: Contract prep
  |
  +-- Add production contracts and failing tests
  +-- Add source guards for MP3-only, shelf lifecycle, player surface

Phase 1: Global MP3-only audio policy
  |
  +-- Shared MP3-only selector
  +-- IA/FMA/podcast/local/download filters
  +-- Convert or remove active bundled WAV ambient loops

Phase 2: Made For You
  |
  +-- Shelf state machine
  +-- lifecycle fix
  +-- updater backfill
  +-- daily shelf cache

Phase 3: Player context
  |
  +-- PlaybackContext
  +-- activeMediaKind
  +-- persisted mediaKindHint/session.mediaKind
  +-- direct book/live paths
  +-- surface spec tests

Phase 4: Live Music validation
  |
  +-- metadata/file validator
  +-- store state
  +-- detail single-file fix

Phase 5: Process hardening
  |
  +-- AGENTS regression contract
  +-- PR template
  +-- source guards
```

Dependency rule:

- Phase 1 must land before candidate validation work so every service uses the same MP3-only policy.
- Phase 3 must land before or alongside Live Music playback changes because Live Music and Book For You both use direct album/sequence playback.
- Phase 5 can start early but should be finalized after phases 1-4 reveal the exact tests and commands worth requiring.

## Data-Model Deltas

Additive only.

| Area | Required? | Delta | Safety |
|---|---:|---|---|
| Made For You backfill | Yes | `UserDefaults` integer `tasteProfileBackfillVersion` | No schema migration; rerunnable if not marked complete |
| Made For You profile | No new table | Reuse `taste_profile_terms`, `taste_seen_identifiers`, `reco_surfaced` | Existing SQLite tables |
| Made For You daily cache | Yes | `made_for_you_daily_cache(day, position, track_id, source, created_at)` | Additive; cache rebuildable |
| Live Music entry cache | Yes | Add optional Codable fields to `LiveMusicEntry` | Backward-compatible decoder or cache invalidation |
| Playback context | Yes | `PlaybackContext` published on `PlayerViewModel` | No destructive data change |
| Playback resume context | Yes | `UserDefaults session.mediaKind` and nullable/defaulted playlist `media_kind_hint` | Additive and defaulted |
| Global MP3 policy | Yes | Shared selector plus source guards; bundled WAV active paths converted/removed | No user data loss |
| Process gates | Yes | `AGENTS.md`, PR template, XCTest source-guard tests | No runtime data impact |

Database migration guarantees:

- Do not delete or rewrite existing user data.
- Do not change required columns on existing tables.
- Do not clear play history as part of backfill.
- If a nullable column is added later, default it to `NULL` and keep inference fallback.
- New cache tables must be rebuildable and safe to clear.

## Implementation Steps

### Phase 0 - Contract Prep

Branch: `quality/regression-contract-tests`

Steps:

1. Add failing or pending contract tests for:
   - Made For You section lifecycle/state.
   - Existing-user taste-profile backfill.
   - Playback context for Book For You.
   - Live Music validation rejection paths.
2. Add minimal production seams/protocols only if required for deterministic tests.
3. Do not change user-facing behavior in this phase unless needed to compile tests.

Verification:

```
xcodegen generate
xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ParsoMusicTests
```

Expected result before implementation: targeted tests should fail for the known bugs. Keep tests and fixes in the same PR and include failing-before-fix evidence in the PR notes.

### Phase 1 - Global MP3-Only Audio Policy

Branch: `fix/global-mp3-only-audio-policy`

Steps:

1. Extract a shared MP3-only selector.
2. Update IA item expansion, IA search playback, FMA, podcast/RSS, local import, download/cache, Live Music, Made For You, Book For You, playlists, and ambient playback to reject every non-MP3 file before playback.
3. Convert active bundled ambient WAV assets to MP3 or remove WAV from active playback paths.
4. Add source guards and unit tests proving Ogg, FLAC, M4A, AAC, Opus, WAV, SHN, video, and metadata-only files are rejected.

Acceptance criteria:

- MP3 Layer 3, VBR MP3, IA `VBR MP3`, `128Kbps MP3`, `64Kbps MP3`, `MP3`, and `.mp3` files are accepted.
- Every non-MP3 format is rejected before `audioPlayer.play`.
- No active playback path points at bundled WAV assets.

### Phase 2 - Made For You

Branch: `fix/made-for-you-visibility-backfill`

Steps:

1. Implement `MadeForYouShelfStore`.
2. Make `MadeForYouSection` always mount.
3. Add one-time existing-user backfill.
4. Move cold-start fallback out of the view.
5. Add `made_for_you_daily_cache`.
6. Update or remove obsolete weak tests.

Acceptance criteria:

- Fresh user, skipped onboarding: section is visible.
- Fresh user, completed onboarding: section loads tracks or visible retry/empty state.
- Existing user with play history but no profile: backfill runs once and section is visible.

### Phase 3 - Player Context And Time Controls

Branch: `fix/player-playback-context-surfaces`

Steps:

1. Add `PlaybackContext`.
2. Add `activeMediaKind`.
3. Add persisted `session.mediaKind` and playlist `media_kind_hint`.
4. Set context in all playback entry points.
5. Route `NowPlayingSheet` through `activeMediaKind`.
6. Add `PlayerSurfaceSpec` and tests for required controls.
7. Add UI accessibility identifiers for scrubber/time controls.

Acceptance criteria:

- Book For You opens audiobook/spoken controls.
- Every finite non-ambient surface shows scrubber, elapsed, and remaining.
- Audiobook/lecture surfaces also show work-level time left.
- Lock-screen/remote content mode matches the active surface.

### Phase 4 - Live Music Validation

Branch: `fix/live-music-validation`

Steps:

1. Use the shared MP3-only audio selector from Phase 1.
2. Add `LiveMusicCandidateValidator`.
3. Publish only validated entries.
4. Add typed store state and visible empty/error state.
5. Fix detail view to accept single-file playable recordings.

Acceptance criteria:

- SHN-only or no-audio item is skipped or shown as a visible no-result state, never as a playable card.
- FLAC/Ogg/M4A/AAC/Opus/WAV/video items are skipped by the global MP3-only policy.
- Loaded card has title and date.
- Detail view shows tracks for single-file and multi-file valid entries.
- Play button either starts validated tracks or shows a clear error.

### Phase 5 - Agent Process Gates

Branch: `chore/regression-quality-gates`

Steps:

1. Update `AGENTS.md`.
2. Add `.github/pull_request_template.md`.
3. Add source guards for known dangerous patterns.
4. Add or update README only if user-facing behavior/setup changed.

Acceptance criteria:

- Future PRs have a checklist for these recurring regressions.
- Source guards fail on the exact known anti-patterns.
- Final PR notes include commands run and any skipped checks.

## Testing Strategy

Minimum local gate per implementation phase:

```
xcodegen generate
xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ParsoMusicTests
```

Additional phase-specific gates:

- Made For You:
  - `-only-testing:ParsoMusicTests/MadeForYouShelfStoreTests`
  - `-only-testing:ParsoMusicTests/MadeForYouVisibilityTests`

- Player Context:
  - `-only-testing:ParsoMusicTests/PlaybackContextTests`
  - `-only-testing:ParsoMusicTests/PlayerSurfaceSpecTests`
  - `-only-testing:ParsoMusicTests/AudioPlayerServiceContentModeTests`

- Global MP3 Policy:
  - `-only-testing:ParsoMusicTests/AudioFormatPolicyTests`
  - `-only-testing:ParsoMusicTests/RegressionContractSourceTests`

- Live Music:
  - `-only-testing:ParsoMusicTests/LiveMusicCandidateValidatorTests`
  - `-only-testing:ParsoMusicTests/LiveMusicOnThisDayTests`
  - Required before merging the Live Music phase: `-only-testing:ParsoMusicIntegrationTests/LiveMusicOnThisDayIntegrationTests`

- UI smoke:
  - Add deterministic launch arguments for fake Made For You, fake Book For You, and fake Live Music data.
  - Run only the targeted UI tests for player controls and Live Music loaded/empty state.

## Settled Decisions

- Each phase includes failing tests and fixes in the same PR, with PR notes showing the failing-before-fix evidence.
- Playback context persistence is included in Player Context phase; do not defer it.
- Global MP3 policy lands first, Player Context lands before Live Music playback changes, and Live Music validation follows.
- The PR template blocks merge for Listen/player changes without targeted UI smoke evidence.
