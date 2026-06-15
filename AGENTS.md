# AGENTS.md — Lorewave Coding Guidelines

_General agentic coding guidelines. Not tool-specific — works for any AI coding assistant._

## Project overview

- **Name**: Lorewave (bundle ID: `guru.parso.ios-radio-app`)
- **Type**: Free, ad-free audio streaming app — 3-tab iOS-native player (Listen, Library, Search)
- **Sources**: Internet Archive, Oxford Lectures, podcast RSS, FMA, bundled ambient
- **iOS**: 17.0+, Swift 5.9, SwiftUI + MVVM
- **Project generation**: XcodeGen (`project.yml`)
- **Dependencies**: SQLite.swift 0.15+ (SPM)

## Build & test

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

**Always regenerate the Xcode project** after adding new `.swift` files — they aren't auto-discovered.

## Source tree

```
ParsoRadio/
├── App/ParsoRadioApp.swift         # @main entry, DI wiring
├── Core/
│   ├── Models/                     # Channel, Track, Playlist, Bookmark, License
│   ├── Services/
│   │   ├── API/                    # InternetArchive, FMA, PodcastRSS services
│   │   ├── Playback/               # AudioPlayer, QueueManager, caching
│   │   ├── Storage/                # DatabaseService (SQLite), FileStorage
│   │   ├── CurationManifest.swift  # LiveCurationStore (in-memory DB snapshot)
│   │   ├── CustomChannelsStore.swift # Per-channel JSON I/O (import/export only)
│   │   └── ...
│   └── Tests/                      # Unit tests (ParsoMusicTests target)
├── Integration/Tests/              # Network-dependent tests
├── Resources/                      # Assets, audio, curated-channels/ JSONs
├── Utilities/                      # Extensions, Logger, SharedViews, Protocols
├── ViewModels/                     # PlayerViewModel, PlaylistViewModel, etc.
└── Views/                          # RootTabView, NowPlayingSheet, MiniPlayer, curator views, etc.
```

## Architecture rules

### Curation architecture (DO NOT REGRESS)

```
  INSTALL/UPDATE (one-time)
    per-channel JSON → import to SQLite curation table
    (only if DB has zero verdicts for that channel)

  RUNTIME (ongoing)
    Approve/Reject → setCuration() → SQLite curation table
                    → reload() → in-memory LiveCurationStore
                    → QueueManager reads from in-memory pool

  SHARE (one-time)
    Export: DB verdicts → JSON/CSV
    Import: JSON file → parse → setCuration() → reload()
```

### NEVER:
- Write to per-channel JSON files from verdict methods
- Add JSON fallback to `LiveCurationStore.pool(for:)`
- Delete curation rows without channel filter in `pruneChannelTracks()`
- Delete curation rows in `evictOldTracks()` — verdicts survive track eviction

### DB is the sole source of truth for curation. JSON files are import/export only.

## Key invariants

- All ViewModels are `@MainActor`
- All DB access goes through a serial `DispatchQueue`, bridged via `withCheckedContinuation`
- `currentChannel` IS `@Published` — do not revert to plain `var`
- `playbackContextToken` prevents stale `playTrack` calls during rapid skip/back
- `curationCounts()` JOINs tracks table to exclude orphaned rows
- `failedAuditionTrackId` is set BEFORE `currentTrack` is cleared on failure

## Adding code

- Use `Double.formattedTime` / `TimeInterval.formattedTime` for time formatting
- Use `ChannelCategoryStyle.color(for:)` / `.gradient(for:)` / `.icon(for:)`
- Use `SharedViews.infoRow(_:_:)` for info rows in detail views
- Follow existing SwiftUI patterns in neighboring files
- No comments unless truly necessary — code should be self-documenting

## Test patterns

- Tests use `@testable import ParsoMusic`
- DB tests use `try DatabaseService(path: ":memory:")` for isolated SQLite
- QueueManager tests inject custom `manifestPool` closure for curated channels
- IA service tests use `MockURLProtocol` (static, not parallel-safe)
- `FakeAudioEngine` provides deterministic playback control
- Tests using shared singletons may leak state — run sequentially

## Common pitfalls

- **Adding new .swift files → must run `xcodegen generate`**
- XCTest test order is alphabetical
- Track struct init: `partNumber` before `parentIdentifier`
- Channel init: `category` before `icon`, `preferredSource` before `feedURL`
- AVPlayer time observer fires on timer, not audio progress — zero ticks do NOT confirm playback
- `importBundledCurationsIfNeeded` is one-time only per channel

## Git workflow

- Push to `main` triggers CI (unit tests → integration tests → TestFlight build)
- A **pre-push hook** runs unit tests locally and blocks the push if any test fails
- **ALWAYS run tests locally before pushing** — guard against push rejection:
  ```bash
  xcodegen generate
  xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:ParsoMusicTests
  ```
- Remote: `git@github.com:johnarleyburns/parso-radio-ios-app.git`
- CI status: `gh run list --limit 1 --branch main`
