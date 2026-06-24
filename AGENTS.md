# AGENTS.md — Lorewave Coding Guidelines

_General agentic coding guidelines. Not tool-specific — works for any AI coding assistant._

## Project Overview

- **Name**: Lorewave (bundle ID: `guru.parso.ios-radio-app`)
- **Type**: Free, ad-free audio streaming app — 3-tab iOS-native player (Listen, Library, Search)
- **Sources**: Internet Archive, Oxford Lectures, podcast RSS, FMA, bundled ambient
- **iOS Target**: 17.0+, Swift 5.9, SwiftUI + MVVM
- **Project Generation**: XcodeGen (`project.yml`)
- **Dependencies**: SQLite.swift 0.15+ (SPM)

---

## Build & Test

```bash
# Regenerate Xcode project (REQUIRED after adding/removing files)
xcodegen generate

# Build
xcodebuild -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' build

# Run unit tests
xcodebuild -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' \
  test -only-testing:ParsoMusicTests

# Run integration tests (hits real IA APIs, slow)
xcodebuild -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' \
  test -only-testing:ParsoMusicIntegrationTests
```

**Always regenerate the Xcode project (`xcodegen generate`)** after adding or removing `.swift` files — they are not automatically discovered by the build system.

---

## Dev Methodology (Plan → Implement, Phase by Phase)

This rigid framework governs how all non-trivial features, refactors, and structural changes are handled.

### 1. Plan to Disk First (Section by Section)
Before writing any application code or modifying existing models, you must document the architecture changes on disk:
- Write comprehensive design documents under `plans/<topic>/<date>/`.
- Structure the directory with `00-overview.md` (containing raw notes, design principles, high-level roadmap, and cross-cutting decisions), followed by dedicated files per feature area.
- Research existing web implementations, competitors, and the current codebase *before* finalizing each section. Ground every entry in the exact physical files it will touch.
- **Each design section must follow this strict anatomy**:
  $$\text{Problem} \longrightarrow \text{Current Behavior} \longrightarrow \text{Research Signal} \longrightarrow \text{Design (with ASCII mockups)} \longrightarrow \text{Data-Model Deltas} \longrightarrow \text{Implementation Steps} \longrightarrow \text{Testing Strategy} \longrightarrow \text{Open Questions}$$
- Capture every critical decision requiring developer validation in an isolated **decision sheet**. Once answered, record the result verbatim in `decisions.md`. Do not re-litigate settled items.
- Consolidate all schema deltas, database migration safety guarantees, and a **phased rollout table** (one branch and PR per phase, clearly outlining dependencies) in the final planning section.

### 2. Implement Phase by Phase (One PR Each)
Execution must move iteratively and safely:
- Before starting a phase, update `current_state.md` to track implementation velocity and structural status.
- Create a distinct git branch per phase. If a phase depends on unmerged upstream work, **stack** the branch (branch off the dependency and merge siblings in) rather than branching directly off `main` to maintain a cleanly buildable dependency chain.
- Isolate logic cleanly: Core playback states, database routines, and ingest models live inside the pure core layer (headlessly test-verifiable with `xcodebuild test`); keep SwiftUI views thin and decoupled on top.
- Schema modifications must be **additive only** (optional or defaulted fields, avoiding destructive migrations) to guarantee local database continuity.
- **Verify, then commit/push/PR**: Run local unit tests to gate the changes. If the `xcodebuild` UI/Simulator suite exhibits environment degradation (e.g., ~45s launch ballooning or `no debugger version`), clear the environment locally:
  ```bash
  killall -9 com.apple.CoreSimulator.CoreSimulatorService
  ```
- Always reference spec IDs or feature descriptors in commit headers and append the `Co-Authored-By` trailer when appropriate.

### 3. Close Out Completed Plans
Once implementation of a planned phase is done, use the same closeout flow every time:
- Re-read the original plan and compare it against the implementation, including touched files, data-model changes, UI behavior, tests, and open questions.
- Fix any discrepancies between the plan and implementation before declaring the phase complete. If the implementation intentionally diverged, record the reason in the plan or status docs.
- Update `current_state.md` with the actual current state, completed work, known gaps, verification results, and next phase pointers.
- Update `README.md` when the completed work changes the project’s user-facing behavior, setup flow, architecture overview, or operational status.
- After verification and documentation updates are complete, commit the finished phase, merge it to `main`, and push `main` so the remote pipeline reflects the current project state.

---

## Source Tree

```
ParsoRadio/
├── App/ParsoRadioApp.swift         # @main entry, DI wiring
├── Core/
│   ├── Models/                     # Channel, Track, Playlist, Bookmark, License
│   ├── Services/
│   │   ├── API/                    # InternetArchive, FMA, PodcastRSS services
│   │   ├── Playback/               # AudioPlayer, QueueManager, caching
│   │   ├── Storage/                # DatabaseService (SQLite), FileStorage
│   │   └── ...
│   └── Tests/                      # Unit tests (ParsoMusicTests target)
├── Integration/Tests/              # Network-dependent tests
├── Resources/                      # Assets, audio, curated-channels/ JSONs
├── Utilities/                      # Extensions, Logger, SharedViews, Protocols
├── ViewModels/                     # PlayerViewModel, PlaylistViewModel, etc.
└── Views/                          # RootTabView, NowPlayingSheet, MiniPlayer, curator views, etc.
```

---

## Architecture Rules

### Curation Architecture (DO NOT REGRESS)

```
  INSTALL/UPDATE (one-time)
    per-channel JSON → import to SQLite tracks table
    (tagged with channel-stamp isolation tokens)

  RUNTIME (ongoing)
    Channel.matches() → filters SQLite tracks table by stamp
                      → QueueManager reads from filtered pool

  SHARE (one-time)
    Export: DB track data → JSON/CSV
    Import: JSON file → parse → insert/update tracks → reload()
```

### NEVER:
- Write to per-channel JSON files from track fetch or verdict methods.
- Delete tracks without a channel filter during `pruneChannelTracks()`.
- Delete tracks in `evictOldTracks()` that are in active channels.

**The SQLite database is the sole source of truth for track data. JSON files are reserved exclusively for static assets and import/export flows.**

---

## Key Invariants

- **Main Actor Threading**: All ViewModels must be decorated with `@MainActor`.
- **Thread-Safe Storage**: All database access must pass through a dedicated serial `DispatchQueue`, bridged asynchronously via `withCheckedContinuation`.
- **State Propagation**: `currentChannel` MUST remain an explicit `@Published` property — do not revert it to a plain variable.
- **Race Protection**: Use a `playbackContextToken` to invalidate stale `playTrack` calls during rapid skipping or track backtracking.
- **Database Integrity**: The `curationCounts()` operation must explicitly `JOIN` the tracks table to exclude orphaned rows.
- **Error Tracking**: `failedAuditionTrackId` must be mutated and set BEFORE `currentTrack` is cleared out during an audio failure lifecycle.

---

## Coding Conventions

- **Time Formats**: Leverage `Double.formattedTime` or `TimeInterval.formattedTime` for UI-facing audio durations.
- **UI Theming**: Apply styles systematically via `ChannelCategoryStyle.color(for:)`, `.gradient(for:)`, and `.icon(for:)`.
- **Component Reuse**: Render details metadata utilizing the standardized `SharedViews.infoRow(_:_:)` layout wrapper.
- **Accessibility Integration**: Accessibility is non-negotiable. Comprehensive VoiceOver labels, accessibility traits, and explicit Dynamic Type support must scale across every interface component (NFR-2).
- **Self-Documenting Principles**: Write highly semantic, clear code. Avoid inline code comments unless addressing complex algorithmic workarounds or unexpected Apple framework edge-cases.

---

## Test Patterns

- **Target Visibility**: Tests must declare `@testable import ParsoMusic`.
- **Isolated State**: Database unit testing must instantiate an isolated, in-memory engine: `try DatabaseService(path: ":memory:")`.
- **Queue Stubbing**: `QueueManager` tests must inject a custom `manifestPool` closure block to simulate curated channels deterministically.
- **Network Decoupling**: Isolate external Internet Archive service boundaries using `MockURLProtocol` (Note: this protocol configuration is static and not parallel-safe).
- **Audio Control**: Implement `FakeAudioEngine` for reliable, synchronous, and deterministic validation of audio playback control states.
- **Execution Strategy**: Because tests leveraging shared singletons may cross-contaminate state, execute test suites sequentially.

---

## Common Pitfalls

- **Missing Blueprint Files**: Adding a new `.swift` file without subsequently executing `xcodegen generate` will drop the file from compilation targets.
- **Alphabetical Execution**: Remember that XCTest orders and runs test execution cases strictly alphabetically.
- **Initialization Signatures**:
  - `Track` struct init: `partNumber` must precede `parentIdentifier`.
  - `Channel` struct init: `category` must precede `icon`; `preferredSource` must precede `feedURL`.
- **Asynchronous Time Flags**: `AVPlayer` time observers execute on an internal timer loop rather than audio processing progress — zero-valued ticks do NOT provide positive confirmation of active audio playback.
- **Idempotency**: `importBundledCurationsIfNeeded` must strictly fire a single time per channel life-cycle.

---

## Git Workflow

- **Continuous Integration**: Pushing directly to `main` executes the remote pipeline (Unit Tests $\rightarrow$ Integration Tests $\rightarrow$ TestFlight deployment).
- **Local Verification Gate**: A strict local **pre-push hook** handles unit tests and forces failure termination before allowing code pushes upstream.
- **Pre-Push Routine**: Always run your assertions locally before executing git push commands to protect build pipelines:
  ```bash
  xcodegen generate
  xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:ParsoMusicTests
  ```
- **Remote Origin**: `git@github.com:johnarleyburns/parso-radio-ios-app.git`
- **Pipeline Health Check**: Query current execution state via: `gh run list --limit 1 --branch main`

---

## Regression Contract

Before claiming any feature/fix is implemented, verify these invariants hold:

### Made For You
- Section always mounts (no `if showSection` gate in `MadeForYouSection`)
- Section visible even in loading/empty/failed states
- Existing-user play history backfills taste profile once (check `tasteProfileBackfillVersion`)
- Cold-start fallback returns both music and audiobook picks, never hides section
- Daily cache persists shelf content; stale cache rebuilds from network

### Live Music on This Day
- Candidates validated before display (MP3-only, date match, display name)
- No `pool.first` fallback after validation failures
- Empty/error state shown with retry affordance, section never hidden
- Daily cache keys use full `yyyy-MM-dd`

### Player Surface
- `NowPlayingSheet` uses `playerVM.activeMediaKind`, never `currentChannel?.mediaKind ?? .music`
- `PlaybackContext` set in every entry point (channel, playlist, direct, search, audition)
- Book For You / audiobook paths set mediaKind explicitly
- Every finite non-ambient surface renders scrub slider, elapsed time, remaining time
- Audiobook/lecture surfaces render work-level time left

### MP3-Only Audio Policy
- All IA audio selection paths use `MP3AudioFormatSelector` (MP3 Layer 3 / VBR MP3 / `.mp3`)
- No Ogg, FLAC, M4A, AAC, Opus, WAV, SHN in any playback selector
- Bundled ambient WAV files exempt (local offline fallback)

### Verification Gate
- Before commit: `xcodegen generate` if files added/removed
- Before push: full `ParsoMusicTests` gate must pass
- Source guards in `RegressionContractSourceTests` must not fail on fixed patterns
- UI changes require targeted UI test or simulator screenshot evidence
