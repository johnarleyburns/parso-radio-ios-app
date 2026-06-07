# LLM-README.md — Parso Radio (Lorewave) iOS App

## Project overview

- **Name**: Lorewave (bundle ID: `guru.parso.ios-radio-app`)
- **Type**: Free, ad-free audio streaming app with iPod Classic click-wheel UI
- **Sources**: Internet Archive, Oxford Lectures, podcast RSS, FMA, bundled ambient
- **iOS**: 17.0+, Swift 5.9, SwiftUI + MVVM
- **Project generation**: XcodeGen (`project.yml`)
- **Dependencies**: SQLite.swift 0.15+ (SPM)

## Build & test

```bash
# Regenerate Xcode project (required after adding/removing files)
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

A git pre-push hook at `.git/hooks/pre-push` runs unit tests before every push.

## Source tree

```
ParsoRadio/
├── App/ParsoRadioApp.swift         # @main entry, DI wiring
├── Core/
│   ├── Models/                     # Channel, Track, Playlist, Bookmark, License
│   ├── Services/
│   │   ├── API/                    # InternetArchiveService, FMAService, PodcastRSSService, etc.
│   │   ├── Playback/               # AudioPlayerService, QueueManager, CachingResourceLoaderDelegate
│   │   ├── Storage/                # DatabaseService (SQLite), FileStorageService
│   │   ├── CurationManifest.swift  # LiveCurationStore (in-memory DB snapshot)
│   │   ├── CustomChannelsStore.swift # Per-channel JSON I/O (import/export/share only)
│   │   └── ...
│   └── Tests/                      # Unit tests (ParsoMusicTests target)
├── Integration/Tests/              # Network-dependent tests
├── Resources/                      # Assets, audio files, curated-channels/ JSONs, ia_queries.json
├── Utilities/                      # Extensions, Logger, SharedViews, ChannelCategoryStyle, Protocols
├── ViewModels/                     # PlayerViewModel, PlaylistViewModel, SearchViewModel
└── Views/                          # iPodView (main), MainMenuView, CuratorModeView, etc.
```

## Architecture

### MVVM with SwiftUI
- ViewModels are `@MainActor` `ObservableObject` with `@Published` properties
- Views consume ViewModels via `@EnvironmentObject` or `@StateObject`
- `PlayerViewModel` is the central orchestrator (~2100 lines — a God object, needs decomposition)

### Dependency injection
- `ParsoRadioApp` creates shared instances (DatabaseService, DownloadManager, ContributionStore)
- Injected via `@EnvironmentObject` for PlayerViewModel, PlaylistViewModel, OfflineDownloadService
- **Many services are singletons** (`.shared`) — KidsModeController, CustomChannelsStore, ArtworkService, etc.
- `AudioEngine` is the only protocol abstraction; most services are concrete classes

### Key services
| Service | Role |
|---------|------|
| `DatabaseService` | SQLite CRUD for tracks, playlists, positions, history, bookmarks, **curation verdicts** |
| `InternetArchiveService` | IA Solr queries, metadata API, audio URL resolution |
| `AudioPlayerService` | AVPlayer wrapper, streaming cache, remote commands, content modes |
| `QueueManager` | Track selection: approved-only for Curated, weighted-random for registry, sequential for podcasts |
| `LiveCurationStore` | In-memory snapshot of DB-approved tracks. `pool(for:)` is **DB-only** — no JSON fallback |
| `CustomChannelsStore` | Per-channel JSON file I/O for **import/export/share only**, never for runtime playback |

## Curation architecture (critical — do not regress)

### DB is the sole source of truth
```
  INSTALL/UPDATE (one-time)
    per-channel JSON → import to SQLite curation table
    (only if DB has zero verdicts for that channel)

  RUNTIME (ongoing)
    Approve/Reject → setCuration() → SQLite curation table
                    → reload() → in-memory LiveCurationStore
                    → QueueManager reads from in-memory pool

  SHARE (one-time)
    Export: DB verdicts → JSON/CSV via CuratorModeView.prepareExport
    Import: JSON file → parse → setCuration() → reload()
```

### DO NOT:
- Write to per-channel JSON files from verdict methods (these were removed — keep them removed)
- Add per-channel file or bundled manifest fallback to `LiveCurationStore.pool(for:)`
- Delete curation rows in `evictOldTracks()` — verdicts survive track eviction
- Delete curation rows without a `colCurChannel` filter in `pruneChannelTracks()`

### Key methods
- `DatabaseService.setCuration(channelId:trackId:status:)` — write a verdict
- `DatabaseService.exportApprovedByChannel()` — read all approved tracks for export
- `LiveCurationStore.shared.reload(from: db)` — refresh in-memory snapshot from DB
- `LiveCurationStore.shared.pool(for: channelId)` — get approved IDs for QueueManager
- `CustomChannelsStore.shared.importBundledCurationsIfNeeded(db:)` — one-time import + recovery

## Curated channel track selection

QueueManager selects tracks in `_next()`:
1. If channel has `feedURL` → podcast path (newest-first, 30-day dedup)
2. `curated = manifestPool(channel.id)` = `LiveCurationStore.shared.pool(for:)`
3. If `curated` is non-empty → pick from approved pool only (weighted-random or sequential)
4. If `isCuratedCategory` (category == "Curated" && iaQueryEntry != nil) → return nil (manifest-only enforcement)
5. Otherwise → fall through to `db.fetchTracks(forChannel:)` (tag/composer matching)

After load, `pruneChannelTracks` keeps `fetchedIds ∪ approvedIds` (combined single prune).

## Track selection on regular channels

- Registry channels (iaQueryEntry): IA Lucene query → stamp injection → tagged in DB
- Tag channels: IA subject matching + FMA in parallel
- Composer channels: IA + Musopen + FMA in parallel
- The `db.pruneChannelTracks` call in `load(channel:)` keeps only current IA query results (plus approved for Curated)

## Stall watchdog & infinite spinner fix

- AVPlayer's `addPeriodicTimeObserver` fires on a timer (0.25s), NOT based on audio progress
- A stuck/buffering item fires `onTimeUpdate(seconds: 0.0)` repeatedly
- **`confirmPlayback` in `onTimeUpdate` is guarded by `seconds > 0`** — zero ticks do NOT disarm the watchdog
- Stall watchdog fires after `stallTimeout` (20s). `evaluateStall` returns `.skip` or `.giveUp`
- In audition context (curator preview), failure sets `failedAuditionTrackId` before clearing `currentTrack`

## Failed audition track tracking

- `@Published var failedAuditionTrackId: String?` — set BEFORE `currentTrack` is cleared
- Curator views check `playerVM.currentTrack?.id ?? playerVM.failedAuditionTrackId` to identify failed rows
- This is necessary because `handleStallIfNeeded` and `handleLoadFailure` clear `currentTrack` before setting `errorMessage`

## Instant resume for curated/audiobook/lecture channels

- `load(channel:)` checks saved position BEFORE hitting the network
- If the track is in DB and still approved (curated), plays immediately with `isLoading = false`
- Background `Task.detached` refreshes the IA pool via `refreshChannelPool`
- This uses the same combined prune logic as the main load path

## @Published properties on PlayerViewModel

Key published properties for UI binding:
- `@Published var currentChannel: Channel?` — MUST be @Published for view reactivity
- `@Published var currentTrack: Track?`
- `@Published var isPlaying: Bool`, `isLoading: Bool`, `errorMessage: String?`
- `@Published var failedAuditionTrackId: String?` — curator audition failure tracking

## Shared utilities

When adding new code, use these instead of duplicating:
- `Double.formattedTime` / `TimeInterval.formattedTime` — time formatting (h:mm:ss or m:ss)
- `ChannelCategoryStyle.color(for:)` / `.gradient(for:)` / `.icon(for:)` — category UI
- `LicenseDisplay.name(_:)` / `.label(_:)` — license strings and badges
- `SourceDisplay.name(_:)` / `.tag(_:)` — source name and badge
- `BrandGradient.linear` — app-wide brand gradient
- `SharedViews.infoRow(_:_:)` / `.badge(_:color:)` / `SectionHelper.legalSection(...)` — reusable views

## Test patterns

- Tests use `@testable import ParsoMusic`
- DB tests use `try DatabaseService(path: ":memory:")` for isolated in-memory SQLite
- QueueManager tests inject a custom `manifestPool` closure for curated channel testing
- IA service tests use `MockURLProtocol` (static requestHandler, not parallel-safe)
- `FakeAudioEngine` provides deterministic playback control
- PlayerViewModel tests create real service instances (heavy but functional); use `loadTask.cancel()` after `Task.yield()` to avoid network calls

## Common pitfalls

- **Adding new Swift files**: Must run `xcodegen generate` after
- **XCTest test order**: Alphabetical. Tests using shared singletons (LiveCurationStore, CustomChannelsStore) may leak state between tests
- **Track struct parameter order**: `partNumber` before `parentIdentifier` in memberwise init
- **Channel init parameter order**: `category` before `icon`, `preferredSource` before `feedURL`
- **DatabaseService concurrency**: All DB access goes through a serial `DispatchQueue`, bridged to async via `withCheckedContinuation`
- **`currentChannel`**: WAS `var` (not @Published); now IS `@Published`. Do not revert
- **`playbackContextToken`**: Used to abort stale `playTrack` calls (rapid skip/back protection)

## Git workflow

- Push to `main` triggers CI (unit tests → integration tests → TestFlight build)
- Pre-push hook runs unit tests locally when configured
- GitHub account: `johnarleyburns` via SSH (`git@github.com:johnarleyburns/parso-radio-ios-app.git`)
- CI status: `gh run list --limit 1 --branch main`

## CI/CD pipeline

Every push to `main` triggers `.github/workflows/ios.yml`:

```
push to main
  │
  ├──▶ Unit Tests (ParsoMusicTests)
  │      └── ~38 test suites, in-memory SQLite, no network
  │
  ├──▶ Integration Tests (ParsoMusicIntegrationTests)
  │      └── Hits real Internet Archive / Oxford APIs
  │      └── 15-minute timeout, runs only if unit tests pass
  │
  └──▶ TestFlight Build
         └── Runs only if BOTH test suites pass
         └── Signs with Apple Distribution cert from GitHub Secrets
         └── Auto-increments build number from run number
         └── Uploads IPA via altool to App Store Connect
```

**Secrets** stored in GitHub repository settings:
- `APPLE_CERTIFICATE_BASE64` — signing certificate (PKCS#12, base64)
- `APPLE_CERTIFICATE_PASSWORD` — certificate password
- `KEYCHAIN_PASSWORD` — temporary CI keychain password
- `PROVISIONING_PROFILE_BASE64` — App Store provisioning profile (base64)
- `TEAM_ID` — Apple Developer Team ID
- `APPSTORE_API_KEY_ID` / `APPSTORE_API_PRIVATE_KEY` / `APPSTORE_API_ISSUER_ID` — ASC API

## Push methodology

Single-branch workflow — push directly to `main`:

```bash
git push origin main
```
