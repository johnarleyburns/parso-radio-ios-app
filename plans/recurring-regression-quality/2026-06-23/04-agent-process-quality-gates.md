# 04 - Agent Process And Quality Gates

## Problem

The app keeps regressing because implementation claims are not tied to production behavior, exact entry points, or verification. Adding more tests has not helped when tests do not exercise the failing production contracts.

## Current Behavior

Physical files involved:

- `AGENTS.md`
- `README.md`
- `.github/workflows/ios.yml`
- `.github/workflows/diagnose.yml`
- `project.yml`
- `ParsoRadio/Core/Tests/NowPlayingSheetTests.swift`
- `ParsoRadio/Core/Tests/PlayerSurfaceIntegrationTests.swift`
- `ParsoRadio/Core/Tests/MadeForYouVisibilityTests.swift`
- `ParsoRadio/Core/Tests/LiveMusicOnThisDayTests.swift`
- `ParsoRadio/UITests/LiveMusicOnThisDayUITests.swift`
- Future required file: `.github/pull_request_template.md`

Current observed behavior:

- The project has strong AGENTS guidance, but it does not yet include a short regression-contract checklist for these recurring surfaces.
- Existing tests are numerous, but several are assertions about intended values in the test body rather than assertions against production code.
- UI tests check section existence, not loaded content quality or controls.
- There is no explicit "implementation complete means these commands passed and these production paths were exercised" artifact.
- A coding agent can plausibly say "implemented" after changing one path while missing parallel entry points such as book-for-you, live detail, recently played, playlist resume, or search.

## Research Signal

- The Test Pyramid recommends more focused lower-level tests than broad GUI tests, and specifically recommends reproducing high-level failures with lower-level tests before fixing them.
- Google Testing Blog frames a useful feedback loop as fast, reliable, and failure-isolating. The current weak tests are fast but not failure-isolating because they do not call the production resolver/store/validator that regresses.
- For this codebase, the right middle layer is "contract tests": pure or near-pure production state machines for shelves, validators, and surface specs, plus a small number of UI smoke tests with accessibility identifiers.

## Design

Create a project-specific regression workflow.

```
Bug report / handoff
  |
  +-- Reproduce with a failing production-contract test
  |
  +-- Implement smallest production change
  |
  +-- Run targeted test file
  |
  +-- Run ParsoMusicTests gate
  |
  +-- For UI player/listen changes:
        run targeted UI smoke OR provide simulator screenshot notes
  |
  +-- Update plan/current_state/README if behavior changed
  |
  +-- Only then claim complete
```

Regression contract categories:

```
Made For You:
  store state + visible section + upgrader backfill

Live Music:
  candidate validation + loaded/empty state + playable tracks

Player Surface:
  playback context + active media kind + surface spec + UI identifiers

Process:
  no "implemented" claim without changed files, tests, and verification output

Global audio:
  MP3-only selector + source guard against non-MP3 playback
```

## Data-Model Deltas

No app data model changes are required for process gates.

Repository metadata additions:

- Add `.github/pull_request_template.md` with a recurring-regression checklist.
- Update `AGENTS.md` with a concise project-specific regression contract.
- Add source guards as XCTest cases first. A later `Tools/quality/` script may wrap the same checks, but XCTest is the required gate.

## Implementation Steps

1. Add a "Regression Contract" section to `AGENTS.md`.
   - Required before implementation:
     - Identify every production entry point that can reach the feature.
     - Write or update a failing test that calls the production contract.
   - Required before completion:
     - List changed files.
     - List verification commands and results.
     - State any paths not verified.

2. Add a PR template.
   - Include checkboxes for:
     - Made For You visibility/backfill unaffected.
     - Live Music candidates validated before display.
     - Player surface selected by explicit context.
     - Finite non-ambient surfaces expose elapsed, remaining, and scrubber.
     - Audiobook/lecture surfaces expose work-left.
     - MP3-only policy enforced; no Ogg/FLAC/M4A/AAC/Opus/WAV/SHN playback.
     - `xcodegen generate` run if files changed.
     - Unit tests run.

3. Replace weak intent tests with production contract tests.
   - Keep high-level UI tests, but do not rely on them as the only guard.
   - Move control membership into production model code, then assert that model.

4. Add source guards for known dangerous patterns.
   - Reject `currentChannel?.mediaKind ?? .music` in `NowPlayingSheet.swift`.
   - Reject root-gating `if showSection` in `MadeForYouSection.swift`.
   - Reject Live Music fallback paths that return `pool.first` after validation failures.
   - Reject audio selector branches that admit Ogg, FLAC, M4A, AAC, Opus, WAV, SHN, or other non-MP3 formats.

5. Add deterministic fakes.
   - Fake recommendation provider for Made For You.
   - Fake IA metadata session for Live Music.
   - Fake audio engine already exists; extend it to record content-mode changes for context tests.

6. Define implementation-complete language.
   - A coding agent should not write "implemented" unless:
     - the feature path was exercised,
     - tests passed or failures are explicitly explained,
     - and user-facing behavior was checked for UI work.

7. Add a regression ledger.
   - Create `plans/recurring-regression-quality/2026-06-23/regression_ledger.md` during implementation phase.
   - Each regression gets: symptom, root cause, production contract test, fixed commit, verification command.

## Testing Strategy

Process changes should be tested with lightweight repository checks:

- `RegressionContractSourceTests`
  - Source guard for banned patterns.
  - Assert `AGENTS.md` contains the Regression Contract headings.
  - Assert the MP3-only selector does not admit non-MP3 formats.

- `PlayerSurfaceSpecTests`
  - Production model tests for controls.

- `MadeForYouShelfStoreTests`
  - Production state machine tests.

- `LiveMusicCandidateValidatorTests`
  - Production candidate validator tests.

CI/local commands:

```
xcodegen generate
xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ParsoMusicTests
```

For UI changes:

```
xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ParsoMusicUITests
```

Use the exact UI test target name from the project before wiring this command into automation.

## Settled Decisions

- Source guards live in XCTest so they run in the normal local/CI unit-test gate.
- The PR template is required for feature and fix branches touching app code, tests, docs, or project configuration.
- UI smoke evidence is required for every Listen/player-surface change. Use targeted UI tests when deterministic; otherwise include simulator screenshot notes in the PR.
- Coding agents stop at PR creation for these high-risk phases unless a human explicitly asks them to merge to `main`.
