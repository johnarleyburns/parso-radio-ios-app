# Preparation-for-Release Plan

_Full technical plan for 14 pre-release changes. Do not implement — review first._

---

## IMPLEMENTATION ORDER (optimized for dependencies)

```
 Dependencies (arrow = "must happen before")
 ───────────────────────────────────────────
 Task 4 (Localization catalog) ← infrastructure, no deps
 Task 9 (.md cleanup)          ← trivial, no deps
 Task 8 (README CI docs)       ← trivial, no deps
 Task 5 (News skip → 0)        ← 1-line per channel, no deps
   └── Task 12 (Podcasts rename) ← depends on Task 5 for startOffsetSeconds=0
 Task 3 (UI tests)             ← needs project structure, no code deps
 Task 1 (Remove CuratorModeView) ← depends on Task 2 for addAllPartsToReview move
 Task 2 (Move addAllPartsToReview) ← no deps, enables Tasks 1 & 6
 Task 6 (Export this Channel)  ← depends on Task 2
 Task 7 (CLI merge tool)       ← no deps, can parallel
 Task 10 (Decompose PlayerVM)  ← HIGHEST RISK, do LAST after all others pass tests
 Task 11 (Siri intents)        ← moderate complexity, can parallel with 10
 Task 13 (Accessibility audit) ← touches all views, do concurrently with 10/11
 Task 14 (Output this plan)    ← DONE (this file)
```

---

## TASK 1: Remove CuratorModeView, replace with CuratedChannelsListView

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~2 hours |
| **Risk** | Low — CuratorModeView is dead code with zero external callers |
| **Files to modify** | 3 files |
| **Files to delete** | 1 file (`ParsoRadio/Views/CuratorModeView.swift`, 818 lines) |

### Current state
`CuratorModeView.swift` has **zero callers anywhere in the codebase**. It defines 4 types:
- `CuratorModeView` — dead, fully replaced by `CuratedChannelsListView`
- `CuratorReviewView` — dead, fully replaced by `CuratorChannelEditView`
- `CuratorSearchAddView` — **STILL ACTIVE**, used by `CuratorChannelEditView` at `CuratedChannelsListView.swift:577`
- `ShareSheet` — dead, `UIActivityViewController` wrapper with no callers

### Implementation
1. **Extract `CuratorSearchAddView`** (lines 523–808 of `CuratorModeView.swift`) into its own file:
   - `ParsoRadio/Views/CuratorSearchAddView.swift`
   - Also includes the helper `SearchAddRow` and `trackFromGroup()` at lines 801–808
   - Remove the `@ObservedObject private var curator = CuratorController.shared` reference (line 541–542) since it's unused in the isolated view
   - Remove the `let db` parameter since it gets it from the parent view's environment
   - Fix compilation: `CuratorSearchAddView` references `CuratorReviewView.ShareSheet` — extract `ShareSheet` to a shared location or inline it

2. **Delete `CuratorModeView.swift`** entirely.

3. **Update `CuratedChannelsListView.swift`**:
   - The import/reference to `CuratorSearchAddView` (line 577) now points to the new file (same module, no import needed in Swift)
   - Verify `CuratorChannelEditView`'s `NavigationLink` to `CuratorSearchAddView` still compiles

4. **Delete `ParsoRadio/Core/Services/CuratorController.swift`** — it loses its only production consumer. Its tests (`CuratorControllerTests.swift`) can also be deleted.

5. **Run `xcodegen generate`** to add the new file and remove deleted files from the project.

6. **Run unit tests** — confirm no regressions.

### Verification
- Build succeeds
- Unit tests pass (some tests reference `CuratorModeView` — check test files for any `@testable import` references; search shows none)
- `CuratorChannelEditView`'s "Search Archive.org to Add" flow works identically

---

## TASK 2: Move addAllPartsToReview to a service

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~1.5 hours |
| **Risk** | Very low — pure code move, no logic change |
| **Files to modify** | 4 files |
| **Files to create** | 1 file (`ParsoRadio/Core/Services/CurationActions.swift`) |

### Current state
```swift
// Duplicated in TWO view files:
// CuratedChannelsListView.swift:829
// CuratorModeView.swift:455
private func addAllPartsToReview(_ track: Track) async {
    let parentId = track.parentIdentifier ?? track.id
    let parts = await db.fetchTracks(forParentIdentifier: parentId)
    guard !parts.isEmpty else { return }
    await db.saveTracks(parts)
    await db.ensureReviewSet(channelId: channelMeta.id, trackIds: parts.map(\.id))
    await reload()
}
```

### Implementation
1. Create `ParsoRadio/Core/Services/CurationActions.swift`:
   ```swift
   import Foundation

   /// Domain-logic operations for curation workflows. Extracted from views
   /// to eliminate duplication and enable reuse by Channel Info export.
   @MainActor
   final class CurationActions {
       let db: DatabaseService

       init(db: DatabaseService) { self.db = db }

       /// Fetch all sibling parts of a multi-part track and add them to the
       /// review queue for the given curated channel.
       func addAllPartsToReview(track: Track, channelId: String) async {
           let parentId = track.parentIdentifier ?? track.id
           let parts = await db.fetchTracks(forParentIdentifier: parentId)
           guard !parts.isEmpty else { return }
           await db.saveTracks(parts)
           await db.ensureReviewSet(channelId: channelId, trackIds: parts.map(\.id))
       }
   }
   ```

2. Replace in `CuratedChannelsListView.swift`:
   - Inject `@State private var curationActions = CurationActions(db: db)` (or pass `db` already present in `CuratorChannelEditView`)
   - Replace body of `addAllPartsToReview` with `await curationActions.addAllPartsToReview(track: track, channelId: channelMeta.id); await reload()`

3. Replace in `CuratorModeView.swift` — but this file is being deleted in Task 1. When extracting `CuratorSearchAddView`, its call site can reference `CurationActions`.

4. Also wire into Task 6 (Channel Info Export) for the export feature's multi-part handling.

---

## TASK 3: Add UI Tests (local-only, not CI)

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~4 hours |
| **Risk** | Low — new test target, no production code changes |
| **Files to create** | 3–5 files |
| **project.yml change** | New `UITests` target, excluded from CI scheme |

### Implementation
1. **Create XCUITest target** — add to `project.yml`:
   ```yaml
   ParsoMusicUITests:
     type: bundle.ui-testing
     platform: iOS
     deploymentTarget: "17.0"
     sources:
       - path: ParsoRadio/UITests
     dependencies:
       - target: ParsoMusic
     settings:
       base:
         GENERATE_INFOPLIST_FILE: YES
   ```

2. **Exclude from CI**: In the CI scheme, only test `ParsoMusicTests` and `ParsoMusicIntegrationTests` — do NOT add `ParsoMusicUITests` to the CI test phase. Confirm it's excluded from `xcodebuild test` without `-only-testing` filters that would accidentally include it.

3. **Test suite files** (`ParsoRadio/UITests/`):

   `SmokeTests.swift` — launch, tap a channel, verify player appears:
   ```swift
   // Core smoke tests: launch, navigate, play
   func testLaunchAndPlayChannel() {
       app.launch()
       // Accept TOS if showing
       if app.buttons["I Agree"].exists { app.buttons["I Agree"].tap() }
       // Tap a channel row
       app.buttons["Classical Guitar"].firstMatch.tap()
       // Wait for playback
       XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 30))
   }
   ```

   `CuratorUITests.swift` — verify curator mode flows:
   - Navigate to Curated channel → Curate → view tracks
   - Tap track → verify track info sheet appears
   - Approve a track → verify it moves to Approved tab

   `SearchUITests.swift` — verify search:
   - Tap search bar → type "beethoven" → verify results appear
   - Tap result → verify track info sheet appears

   `AccessibilityUITests.swift` — run with VoiceOver:
   - Use `XCUIApplication(bundleIdentifier: ...)` with `launchArguments` for accessibility presets
   - Verify critical labels and actions

4. **Run locally only**: Add to `LLM-README.md` (renamed `README.md`):
   ```bash
   # UI tests (local only — NOT run on CI)
   xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     -only-testing:ParsoMusicUITests
   ```

---

## TASK 4: LocalizedStringKey catalog (English only)

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~6 hours |
| **Risk** | Medium — touching every UI string across all views, potential for typos/missed strings |
| **Files to create** | 1 file (`ParsoRadio/Resources/Localizable.xcstrings`) |
| **Files to modify** | ~35 Swift view files |

### Implementation
1. **Create String Catalog** in Xcode:
   - `File → New → File → Resource → String Catalog`
   - Name: `Localizable.xcstrings`
   - Place in `ParsoRadio/Resources/`
   - Delete all auto-generated locale subfolders — keep only `en` entry

2. **Migration strategy** — Systematic, file-by-file:

   **Phase A — Infrastructure views** (lowest risk):
   - `AboutView.swift`
   - `TermsView.swift`
   - `WheelHelpView.swift`
   - `SettingsView.swift`

   **Phase B — Content views**:
   - `ChannelInfoView.swift`
   - `ChapterListView.swift`
   - `ChannelSelectorView.swift`
   - `ChannelListView.swift`

   **Phase C — Playlist views**:
   - `PlaylistsScreen.swift`
   - `PlaylistDetailView.swift`
   - `PlaylistListView.swift`
   - `AddToPlaylistSheet.swift`
   - `AddItemToPlaylistSheet.swift`

   **Phase D — Curator views**:
   - `CuratedChannelsListView.swift` (and extracted `CuratorSearchAddView.swift`)
   - `CuratorChannelEditView` (nested in `CuratedChannelsListView.swift`)

   **Phase E — Core player views** (highest risk — touch LAST):
   - `iPodView.swift` — the most complex view, many strings
   - `NowPlayingView.swift`
   - `PlayerView.swift`
   - `MainMenuView.swift`
   - `SearchView.swift`
   - `SplashView.swift`

   **Phase F — Support views**:
   - `ContributionSupportView.swift`
   - `ContributionToast.swift`
   - `AgeGateView.swift`
   - `KidsMenuView.swift`
   - `RecentlyPlayedScreen.swift`
   - `AddTracksView.swift`

3. **String replacement pattern**:
   ```swift
   // Before:
   Text("Curate this Channel")
   Button("Approve") { ... }

   // After:
   Text("curate_channel_button", tableName: "Localizable")
   Button("approve_button", tableName: "Localizable") { ... }
   ```
   Use the `String(localized:)` initializer (Swift 5.9+):
   ```swift
   Text(String(localized: "curate_channel_button"))
   Button(String(localized: "approve_button")) { ... }
   ```

4. **Naming convention** for keys: `snake_case` with semantic grouping:
   - `button_*` — button labels
   - `label_*` — static text labels
   - `hint_*` — accessibility hints
   - `error_*` — error messages
   - `channel_*` — channel-related strings
   - `settings_*` — settings screen strings

5. **Accessibility strings**: `accessibilityLabel`, `accessibilityHint`, `accessibilityValue` also get keys — important for visually impaired users. DO NOT SKIP THESE.

6. **DO NOT localize**:
   - Debug strings (`#if DEBUG` blocks)
   - Log messages (`Logger`)
   - Technical IDs, URLs, JSON keys
   - Developer-facing error messages
   - Channel names (these are dynamic/user-facing but stored in channel metadata, not UI strings)

7. **After migration**: Verify all strings appear in the catalog. Xcode shows a warning if a key is missing from the catalog. Run the app and visually verify screens.

8. **Add `defaultLocalization: en`** to `project.yml` info properties.

### Risk mitigation
- Commit after each Phase so reverting a single phase is easy
- Run tests after each phase
- Use `xcrun xcstringstool` to validate the catalog before final commit

---

## TASK 5: News channels — remove startOffsetSeconds (start at 0:00)

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~30 minutes |
| **Risk** | None — simple data change with no logic impact |
| **Files to modify** | 1 file (`ParsoRadio/Core/Models/Channel.swift`) |

### Implementation
In `Channel.swift`, change all 7 news channel `startOffsetSeconds` values to `nil` (or remove the parameter):

| Line | Channel | Current | New |
|------|---------|---------|-----|
| 255 | NPR Up First | `148` | `nil` (remove param) |
| 263 | PBS NewsHour | `30` | `nil` |
| 271 | Democracy Now! | `17` | `nil` |
| 279 | NPR 1A | `24` | `nil` |
| 291 | BBC Global News | `96` | `nil` |
| 299 | DW Inside Europe | `18` | `nil` |
| 307 | CBC As It Happens | `35` | `nil` |

### Rationale
Podcast RSS terms of service typically require playing episodes as-delivered. Skipping intro filler is editorial modification. Setting to 0:00 ensures compliance. The autoseek codepath (`PlayerViewModel.swift:1130–1135`) gracefully no-ops when `startOffsetSeconds` is nil.

### Verification
- Confirm all 7 channels play from 0:00
- No regressions in news newest-episode logic (lines 660–683) — this is independent of startOffsetSeconds
- Update `ChannelTests.swift` lines 267–285 if they assert specific startOffsetSeconds values

---

## TASK 6: "Export this Channel" button in Channel Info

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~2 hours |
| **Risk** | Low — new button in existing view, uses existing DB query |
| **Files to modify** | 1 file (`ParsoRadio/Views/ChannelInfoView.swift`) |

### Implementation
1. In `ChannelInfoView.swift`, add a new `Section` after "Curate this Channel" (line 48–58):

   ```swift
   // Export this Channel (for curated channels with approved tracks)
   if channel.category == "Curated",
      !LiveCurationStore.shared.pool(for: channel.id).isEmpty {
       Section {
           ShareLink(item: exportJSON, preview: SharePreview(
               "\(displayName) Curated Tracks",
               image: Image(systemName: channel.icon)))
           {
               Label("Export this Channel", systemImage: "square.and.arrow.up")
                   .foregroundStyle(Color.accentColor)
           }
       }
   }
   ```

2. Add computed property for the export:
   ```swift
   private var exportJSON: String {
       let tracks = await DatabaseService.shared.fetchApprovedTracks(
           forChannelId: channel.id)
       let entries = tracks.map {
           ChannelDefinition.ApprovedEntry(
               id: $0.id,
               title: $0.title,
               creator: $0.artist,
               duration: $0.duration,
               parentIdentifier: $0.parentIdentifier
           )
       }
       let info = ChannelDefinition.Info(
           id: channel.id,
           name: displayName,
           icon: channel.icon,
           iaQuery: channel.iaQueryEntry?.iaQuery
       )
       let def = ChannelDefinition(
           version: 1,
           channel: info,
           updatedAt: ISO8601DateFormatter().string(from: Date()),
           approved: entries,
           rejected: []
       )
       let encoder = JSONEncoder()
       encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
       guard let data = try? encoder.encode(def) else { return "{}" }
       return String(data: data, encoding: .utf8) ?? "{}"
   }
   ```

3. **Make it async** — `LiveCurationStore` pool check is synchronous (in-memory), but `fetchApprovedTracks` is async. Use `.task { }` to preload or make the button async:
   ```swift
   @State private var exportData: String? = nil
   
   // In the button:
   Button {
       Task {
           exportData = await buildExportJSON()
       }
   } label: { ... }
   .sheet(item: $exportData) { ... }  // or use ShareLink when data is ready
   ```

   Alternatively, use `ShareLink(item:preview:)` with a `Transferable`-conforming type. Simpler approach: use `.fileExporter` modifier to save to Files, or `ShareLink` with a `String`.

4. **The export format** matches `ChannelDefinition` (same JSON shape as the bundled curated channels in `Resources/curated-channels/`), so exported files can be:
   - Shared with other users (import in CustomChannelsStore)
   - Merged back into the app's bundled defaults via the CLI tool (Task 7)
   - Emailed to the developer for inclusion in future app updates

### Verification
- Navigate to a curated channel with approved tracks → Channel Info → "Export this Channel" appears
- Tap it → share sheet opens with JSON file
- File content matches `ChannelDefinition` shape
- Exported file can be imported back into the app via `CustomChannelsStore`

---

## TASK 7: CLI tool to merge/replace curated channel defaults

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~4 hours |
| **Risk** | Low — standalone tool, no app code changes |
| **Files to create** | 1 directory + ~3 Swift files |
| **Location** | `Tools/merge-curation/` (or similar root-level directory) |

### Implementation
1. **Create Swift Package Manager executable**:
   ```
   Tools/
   └── merge-curation/
       ├── Package.swift
       └── Sources/
           └── merge-curation/
               ├── main.swift
               ├── ChannelDefinition.swift    (copy of the model)
               └── MergeEngine.swift
   ```

2. **Package.swift**:
   ```swift
   // swift-tools-version: 5.9
   import PackageDescription
   let package = Package(
       name: "merge-curation",
       platforms: [.macOS(.v13)],
       targets: [
           .executableTarget(name: "merge-curation")
       ]
   )
   ```

3. **Usage**:
   ```bash
   # Merge: add app-approved tracks to the bundled default (skip duplicates):
   swift run merge-curation merge \
     --input /path/to/exported-guitar-classical.json \
     --target Resources/curated-channels/guitar-classical.json

   # Replace: completely overwrite the bundled default:
   swift run merge-curation replace \
     --input /path/to/exported-guitar-classical.json \
     --target Resources/curated-channels/guitar-classical.json

   # Dry-run: show what WOULD change without writing:
   swift run merge-curation merge --dry-run \
     --input /path/to/exported.json \
     --target Resources/curated-channels/guitar-classical.json
   ```

4. **Merge logic** (`MergeEngine.swift`):
   ```swift
   enum Mode { case merge, replace }
   
   func apply(input: ChannelDefinition, target: ChannelDefinition, mode: Mode) 
       -> (ChannelDefinition, diff: Diff) {
       switch mode {
       case .replace:
           // Keep target's channel info (id, name, icon, iaQuery) 
           // from source tree — those are hand-maintained
           var result = input
           result.channel = target.channel
           result.updatedAt = ISO8601DateFormatter().string(from: Date())
           return (result, .replaced(input.approved.count - target.approved.count))
       case .merge:
           var merged = target
           let existingIds = Set(target.approved.map(\.id))
           var added = 0, skipped = 0
           for entry in input.approved where !existingIds.contains(entry.id) {
               merged.approved.append(entry)
               added += 1
           }
           skipped = input.approved.count - added
           merged.updatedAt = ISO8601DateFormatter().string(from: Date())
           return (merged, .merged(added: added, skipped: skipped))
       }
   }
   ```

5. **Write output**: Pretty-print JSON back to `--target` path.
   Dry-run mode prints the diff but doesn't write.

6. **Add to `LLM-README.md`**: Document the tool and its usage.

### Verification
- Merge an exported JSON into a bundled default without duplicating existing entries
- Replace a bundled default with a new curated JSON
- Dry-run shows correct diff without modifying files
- `git diff` after merge/replace shows expected changes

---

## TASK 8: GitHub Action pipeline documentation in README

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~30 minutes |
| **Risk** | None — documentation only |
| **Files to modify** | 1 file (`README.md`, currently deleted → will be recreated) |

### Implementation
Add to `README.md` a "CI/CD Pipeline" section based on `.github/workflows/ios.yml`:

```markdown
## CI/CD Pipeline

Every push to `main` triggers a GitHub Actions workflow (`.github/workflows/ios.yml`):

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
         └── Auto-increments build number (run number - 103)
         └── Uploads IPA via altool to App Store Connect
```

**Push methodology**: Push directly to `main` (single-branch workflow):
```bash
git push origin main
```

The pre-push hook at `.git/hooks/pre-push` runs unit tests locally before push (if configured).

**Secrets** stored in GitHub repository settings:
- `APPLE_CERTIFICATE_BASE64` — Apple Distribution signing certificate (PKCS#12, base64)
- `APPLE_CERTIFICATE_PASSWORD` — certificate password
- `KEYCHAIN_PASSWORD` — temporary CI keychain password
- `PROVISIONING_PROFILE_BASE64` — App Store provisioning profile (base64)
- `TEAM_ID` — Apple Developer Team ID
- `APPSTORE_API_KEY_ID` — App Store Connect API key ID
- `APPSTORE_API_PRIVATE_KEY` — App Store Connect API private key (PEM)
- `APPSTORE_API_ISSUER_ID` — App Store Connect API issuer ID
```

---

## TASK 9: Cleanup all .md files

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~15 minutes |
| **Risk** | None — file deletions only. Keep content that matters. |

### Files to KEEP
| File | Reason |
|------|--------|
| `README.md` | Recreated (formerly `LLM-README.md`). Main project docs — architecture, build instructions, CI/CD, testing, coding conventions. |
| `AGENTS.md` (new) | Agentic coding guidelines. Replaces `LLM-README.md` purpose. Content: general coding conventions, architecture invariants, test patterns, common pitfalls. Not Claude-specific — works for any AI coding assistant. |
| `preparation-for-release.md` | This plan file. Delete after all tasks complete. |
| `lorewave-privacy.html` | Published privacy policy HTML — linked from App Store Connect. Keep. |

### Files to DELETE
| File | Why delete |
|------|-----------|
| `LLM-README.md` | Content merged into `README.md` + `AGENTS.md` |
| `CONTRIBUTIONS-PROPOSAL.md` | Archive — feature is already implemented, proposal no longer needed |
| `CONTRIBUTIONS-SETUP.md` | Archive — setup instructions are already in `FOR_APPSTORE_REVIEWERS.md` + code comments |
| `FOR_APPSTORE_REVIEWERS.md` | Archive — one-time submission doc, no longer needed after approval. Keep content in App Store Connect "Review Notes" field instead. |
| `plan_jun5.md` | Archive — plan fully implemented |
| `.opencode/plans/fix-curation-resume.md` | Archive — fix already applied in code |

### AGENTS.md content outline
```markdown
# AGENTS.md — Lorewave Coding Guidelines

## Project context (same as README summary)
## Never-do list (curation architecture invariants from LLM-README.md)
## Architecture rules
  - DB is sole source of truth for curation
  - LiveCurationStore reads from DB only
  - JSON files are import/export ONLY
  - @MainActor for all ViewModels
  - No singletons leaked between test cases
## Adding new files → run xcodegen generate
## Test patterns (in-memory DB, FakeAudioEngine, MockURLProtocol)
## Common pitfalls (parameter order, @Published, context tokens)
## Build & test commands
```

---

## TASK 10: Decompose PlayerViewModel (CONSERVATIVE — no refactoring)

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~8 hours (high-risk, must verify exhaustively) |
| **Risk** | **HIGH** — PlayerViewModel is the critical path for all playback |
| **Files to create** | ~8 new files |
| **Files to modify** | 1 file (`PlayerViewModel.swift` → becomes facade) |
| **Strategy** | Move methods ONLY. Zero logic changes. Verify after each extraction. |

### ⚠️ CRITICAL RULES
1. **NEVER change a single line of logic.** Only move method bodies.
2. **After each file extraction, run ALL tests.** If any test fails, revert and re-examine.
3. **PlayerViewModel remains the `@MainActor` facade.** Sub-components are non-ObservableObjects — they read/write to PlayerViewModel's `@Published` properties directly (or via closures).
4. **Preserve exact call-site syntax.** If a method calls `self.someMethod()`, the extracted version calls `vm.someMethod()` or receives a closure.

### Extraction Plan (in order — leaf nodes first)

#### Step 1: `BookmarkController` (~25 lines, 0 dependencies)
Extract: `addBookmarkAtCurrentPosition`, `deleteBookmark`, `seekToBookmark`  
Properties used: `currentTrack`, `currentPosition`, `bookmarksForCurrentTrack`, `db`, `audioPlayer`  
Create: `ParsoRadio/ViewModels/BookmarkController.swift`

```swift
@MainActor
final class BookmarkController {
    unowned let vm: PlayerViewModel
    unowned let db: DatabaseService
    unowned let audioPlayer: AudioPlayerService
    
    init(vm: PlayerViewModel, db: DatabaseService, audioPlayer: AudioPlayerService) {
        self.vm = vm; self.db = db; self.audioPlayer = audioPlayer
    }
    
    func addBookmarkAtCurrentPosition(label: String?) { /* move body */ }
    func deleteBookmark(_ bookmark: Bookmark) { /* move body */ }
    func seekToBookmark(_ bookmark: Bookmark) { /* move body */ }
}
```

PlayerViewModel side: delegate to `bookmarkController.addBookmarkAtCurrentPosition(label:)`.

#### Step 2: `RecommendationEngine` (~50 lines, 0 published deps)
Extract: `fetchRecommendations`  
Properties used: `db` only  
Create: `ParsoRadio/ViewModels/RecommendationEngine.swift`

#### Step 3: `RecentlyPlayedManager` (~70 lines, 0 published deps)
Extract: `recentlyPlayedTracks`, `playRecentTrack`, `removeFromRecentlyPlayed`, `clearRecentlyPlayed`, `clearListeningHistory`  
Properties used: `db`, `audioPlayer`  
Create: `ParsoRadio/ViewModels/RecentlyPlayedManager.swift`

#### Step 4: `KidsModeCoordinator` (~28 lines, minimal deps)
Extract: `enterKidsMode`, `assertKidsModeInvariant`  
Properties used: `currentChannel`, `currentPlaylist`, `playHistory`  
Create: `ParsoRadio/ViewModels/KidsModeCoordinator.swift`

#### Step 5: `PlaybackSettingsManager` (~120 lines, shuffle/repeat/sleep/rate)
Extract: `toggleShuffle`, `toggleRepeat`, `startSleepTimer`, `setSleepAtEndOfTrack`, `cancelSleepTimer`, `isSleepTimerActive`, `setPlaybackRate`, `playbackRateOptions`  
Properties used: `shuffleMode`, `repeatMode`, `sleepTimerEndsAt`, `sleepAtEndOfTrack`, `isPlaying`, `playbackRate`, `audioPlayer`  
Create: `ParsoRadio/ViewModels/PlaybackSettingsManager.swift`

#### Step 6: `SessionPersistenceManager` (~150 lines, moderate risk)
Extract: `saveCurrentSpot`, `saveAutosaveForCurrentTrack`, `deleteAutosaveForTrack`, `autosavePosition`, `persistSession`, `restoreLastSession`  
Properties used: `currentTrack`, `currentChannel`, `currentPlaylist`, `currentPosition`, `trackDuration`, `isAuditioning`, `db`, `UserDefaults.standard`  
**⚠️ Caution**: `persistSession` is called from MANY places (togglePlayPause, skip, back, playTrack, onTimeUpdate, willResignActive). The extracted method must remain callable from all the same call sites.
Create: `ParsoRadio/ViewModels/SessionPersistenceManager.swift`

#### Step 7: `LoadFailureHandler` (~120 lines, moderate risk)
Extract: `classify`, `handleLoadFailure`, `refreshChannelPool`, `prefetchNextURL`  
Properties used: `isLoading`, `loadingMessage`, `currentTrack`, `trackDuration`, `isPlaying`, `errorMessage`, `currentChannel`, `currentPlaylist`, `failedAuditionTrackId`, `channelTrackCount`, `channelMostRecentDate`, `db`, `archiveService`, `playbackContextToken`, `stallModel`  
**⚠️ Caution**: Touches `playbackContextToken` — this must remain accessible from PlayerViewModel.
Create: `ParsoRadio/ViewModels/LoadFailureHandler.swift`

#### Step 8: STOP HERE — keep remaining groups in PlayerViewModel
The remaining groups (PlaybackEventRouter, PlaybackController, TrackPlaybackEngine, ChannelLoader, PlaylistPlaybackEngine) are deeply intertwined via `playbackContextToken`, `stallModel`, `preAuditionState`, and the `audioPlayer` callbacks. Extracting these risks regressions that aren't worth the maintenance benefit. At this point PlayerViewModel should be ~1,200 lines (down from 2,168).

### After extraction — PlayerViewModel remains responsible for:
- `@Published` property declarations (all 27)
- Audio engine callback wiring (PlaybackEventRouter)
- `togglePlayPause`, `skip`, `seek`, `back`, `goToPreviousTrack` (PlaybackController)
- `load(channel:autoPlay:)` (ChannelLoader — the 300-line orchestration method)
- `playTrack`, `advanceToNext`, `handleStallIfNeeded` (TrackPlaybackEngine)
- `loadPlaylist`, `auditionTrack`, `playSearchResult` (PlaylistPlaybackEngine)
- `addEntireItemToPlaylist`, `playEntireCurrentItem` (AlbumBookPlayer)
- `skipToNextBook`, `skipToPreviousBook` (BookNavigation)
- `currentArtwork`, `artworkDominantColor` updates
- `resolveItemParts`, `probeCurrentTrack`
- `clearAllUserData`

### Verification for EACH step:
1. Build succeeds
2. All unit tests pass (`ParsoMusicTests`)
3. All integration tests pass (`ParsoMusicIntegrationTests`)
4. Manual smoke test: launch → play Classical Guitar → verify playback
5. Manual smoke test: curator mode → audition → approve → verify
6. Manual smoke test: playlist → play → verify

---

## TASK 11: Siri Intents

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~6 hours |
| **Risk** | Medium — new target type, entitlements, app group communication |
| **Files to create** | ~5 files in Intents extension |
| **project.yml change** | New `SiriIntents` target |
| **Entitlements** | Add Siri capability to main app + extension |

### Intents to ship

| Intent | Phrase examples | Behavior |
|--------|----------------|----------|
| `PlayLorewave` | "Play Lorewave", "Resume Lorewave" | Restore last session from `UserDefaults`. If none, play Classical Guitar channel. |
| `PlayChannel` | "Play Chamber Music on Lorewave", "Play NPR Up First on Lorewave" | Match channel name from `Channel.defaults`, load it. |
| `PlayNews` | "Play the news on Lorewave" | Shortcut to NPR Up First channel. |

### Implementation

1. **Create Intents Extension target** in `project.yml`:
   ```yaml
   SiriIntents:
     type: app-extension
     platform: iOS
     deploymentTarget: "17.0"
     sources:
       - path: ParsoRadio/SiriIntents
     dependencies:
       - target: ParsoMusic
     settings:
       base:
         GENERATE_INFOPLIST_FILE: YES
         INFOPLIST_KEY_CFBundleDisplayName: Lorewave Intents
         INFOPLIST_KEY_NSExtension:
           NSExtensionAttributes:
             IntentsSupported:
               - PlayLorewaveIntent
               - PlayChannelIntent
               - PlayNewsIntent
   ```

2. **Define Intents** — Use `.intentdefinition` file in Xcode:
   - Create `ParsoRadio/Resources/Intents.intentdefinition`
   - Define 3 custom intents:
   
   **PlayLorewaveIntent**: No parameters. Configurable in Shortcuts app.
   
   **PlayChannelIntent**: 
   - Parameter: `channel` (type: String, resolution via `ChannelResolutionProvider` that matches against `Channel.defaults.map(\.name)`)
   
   **PlayNewsIntent**: No parameters. Hardcoded to `news-nprup-first`.

3. **IntentHandler.swift** (in SiriIntents target):
   ```swift
   import Intents
   
   class IntentHandler: INExtension {
       override func handler(for intent: INIntent) -> Any {
           switch intent {
           case is PlayLorewaveIntent:
               return PlayLorewaveIntentHandler()
           case is PlayChannelIntent:
               return PlayChannelIntentHandler()
           case is PlayNewsIntent:
               return PlayNewsIntentHandler()
           default:
               fatalError("Unknown intent: \(intent)")
           }
       }
   }
   ```

4. **App Group communication**: Intents extension runs in a separate process. To communicate with the main app, use **App Groups** (`UserDefaults(suiteName:)`):
   ```swift
   let shared = UserDefaults(suiteName: "group.guru.parso.ios-radio-app")!
   shared.set("play-channel", forKey: "siri.command")
   shared.set("guitar-classical", forKey: "siri.channelId")
   ```

   Main app observes this key on `scenePhase == .active`:
   ```swift
   .onChange(of: scenePhase) { _, phase in
       if phase == .active { handleSiriCommand() }
   }
   ```

5. **Confirm intent handler** returns `.success(INConfirmIntentResponse...)` with channel metadata displayed on Siri UI.

6. **Handle intent handler** writes to shared UserDefaults, returns `.success(...)`.

7. **Entitlements**: Add Siri capability to both main app and SiriIntents extension in Xcode capabilities (or via `project.yml`).

8. **Donate intents**: In `PlayerViewModel`, after loading a channel:
   ```swift
   if #available(iOS 17.0, *) {
       let intent = PlayChannelIntent()
       intent.channel = channel.name
       let interaction = INInteraction(intent: intent, response: nil)
       interaction.donate()
   }
   ```
   This teaches Siri the user's patterns over time for proactive suggestions.

### Verification
- Build succeeds with SiriIntents target
- "Hey Siri, play Lorewave" → app opens → resumes last track
- "Hey Siri, play Chamber Music on Lorewave" → app opens → loads Chamber Music
- "Hey Siri, play the news on Lorewave" → app opens → loads NPR Up First
- Siri suggestions appear in Spotlight/search after using the app a few times

---

## TASK 12: Podcast subscription + "News" → "Podcasts" rename

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~8 hours |
| **Risk** | Medium-High — SQLite schema change, new UI flow, external API dependency |
| **Files to create** | ~4 files |
| **Files to modify** | ~8 files |

### Part A: Rename "News" → "Podcasts"

**Affected files** (systematic grep result):
| File | Change |
|------|--------|
| `Channel.swift:251–307` | 7 channels: `category: "News"` → `category: "Podcasts"` |
| `ChannelCategoryStyle.swift:10,31,49` | `"News"` case → `"Podcasts"` |
| `MainMenuView.swift:72,286` | `"News"` → `"Podcasts"` |
| `ChannelSelectorView.swift:15` | `"News"` → `"Podcasts"` |
| `SharedUtilitiesTests.swift:71,87` | Update test strings |
| `ChannelTests.swift:262–359` | Update test assertions |
| `RecommendationQueryBuilderTests.swift:31,48` | Update if needed |
| `PodcastRSSServiceTests.swift` | No change (uses "News" only for test channels, not the enum) |

### Part B: User-defined podcast subscriptions

1. **Database schema change**: Add `podcast_subscriptions` table:
   ```swift
   // In DatabaseService.swift
   let podcastSubs = Table("podcast_subscriptions")
   let colPSId = Expression<String>("id")           // UUID
   let colPSName = Expression<String>("name")         // User-given name
   let colPSFeedURL = Expression<String>("feed_url")
   let colPSCreatedAt = Expression<Double>("created_at")
   ```
   Add migration in `migrateSchema()`.

2. **PodcastSubscriptionStore.swift** (new file, `@MainActor ObservableObject`):
   ```swift
   @MainActor
   final class PodcastSubscriptionStore: ObservableObject {
       static let shared = PodcastSubscriptionStore()
       @Published var subscriptions: [PodcastSubscription] = []
       
       func add(name: String, feedURL: String) async { ... }
       func remove(id: String) async { ... }
       func fetchSubscriptions() async { ... }
       
       /// Convert subscription to a playable Channel
       func channel(from sub: PodcastSubscription) -> Channel { ... }
   }
   ```

3. **Dynamic channels in `ChannelSelectorView` and `ChannelListView`**:
   - `PodcastSubscriptionStore.shared.subscriptions` inserted into the "Podcasts" section
   - Each subscription renders as a row with its user-given name
   - On tap: `playerVM.load(channel: channel, autoPlay: true)`

4. **UI for adding subscriptions** — new view `PodcastAddView.swift`:
   ```
   NavigationStack
   ├── "Podcast Feed URL" TextField
   ├── "Fetch & Preview" button
   │   └── Calls PodcastRSSService.fetchTracks() with the user-supplied URL
   │   └── Shows feed title, episode count, most recent episode date
   └── "Subscribe" button → saves to PodcastSubscriptionStore + DB
   ```

5. **Newest-first playback mechanics** — Already handled! Podcast channels use:
   - `QueueManager.nextPodcastTrack()` (QueueManager.swift:221) — sequential newest-first
   - `PlayerViewModel` news newest-episode jump (lines 660–683) — skips to newest if new episode
   - With `startOffsetSeconds` removed (Task 5), all podcasts start at 0:00
   - Remove the hardcoded channel-specific `startOffsetSeconds` code path — ALL podcast channels (including user-subscribed) should honor the same behavior. The `startOffsetSeconds` field stays in `Channel` struct but defaults to nil.

   Small change needed: The "news newest-episode jump" currently checks `channel.feedURL != nil` — this naturally applies to user-subscribed podcast channels too since they'll have `feedURL` set.

6. **Podcast search research** (for the search feed feature):

   | API | Free Tier | Rate Limits | Notes |
   |-----|-----------|-------------|-------|
   | **PodcastIndex** | Yes (developer API key) | 50 req/hour core, 1000+ with verification | Best option. Open API, huge index (4M+ podcasts). Requires free account at podcastindex.org. Full-text search, feed lookup by URL, trending. |
   | **iTunes Search API** | Yes, no key needed | ~20 req/min | Apple's own API. Search podcasts by term. Returns JSON with feed URLs. Limited metadata. Good fallback. |
   | **Listen Notes** | Paid ($100+/mo) | N/A | Best quality but not free. Skip. |

   **Recommended approach**: Use **iTunes Search API** for search (no auth, free, simple):
   ```
   GET https://itunes.apple.com/search?term=npr+up+first&media=podcast&limit=20
   ```
   Returns feed URLs + artwork + episode counts. Add a `PodcastSearchService.swift` that wraps this.

7. **Add search bar to `PodcastAddView`** using iTunes Search API:
   ```
   Search → show results (name, artwork, episode count) → tap → pre-fill URL field → subscribe
   ```

### Verification
- "Podcasts" appears in menu instead of "News"
- All 7 existing news channels work identically (start at 0:00, newest-first)
- Add custom podcast feed → appears in Podcasts list → plays correctly
- Search for podcast → finds results → can subscribe
- Delete subscription → removed from list
- User-subscribed podcasts have same newest-first + bookmark-resume behavior

---

## TASK 13: Full Accessibility Audit

| Aspect | Detail |
|--------|--------|
| **Estimated effort** | ~6 hours |
| **Risk** | Low — accessibility additions, no logic changes |
| **Files to modify** | Most view files (audit + add missing labels) |

### Audit checklist per view

For each view file, verify:

| Criterion | Check |
|-----------|-------|
| **VoiceOver labels** | Every interactive element has `.accessibilityLabel()` or `.accessibilityElement(children: .combine)` |
| **VoiceOver hints** | Actions have `.accessibilityHint()` explaining WHAT happens, not HOW (e.g., "Plays this channel" not "Tap to play") |
| **VoiceOver traits** | Buttons have `.isButton`, headers have `.isHeader`, toggles have `.isToggle` |
| **Dynamic Type** | View supports `.dynamicTypeSize(.medium ... .accessibility2)` — check iPodView already does this |
| **Reduce Motion** | `@Environment(\.accessibilityReduceMotion)` guards animations in iPodView (line 7), ProceduralVisualizerView (line 11) |
| **Reduce Transparency** | `@Environment(\.accessibilityReduceTransparency)` used in MainMenuView (line 24) |
| **High Contrast** | Color is never the sole indicator of state — always pair with icons or text |
| **Focus order** | Tab/swipe order through interactive elements makes logical sense |
| **Minimum touch target** | All interactive elements ≥ 44×44pt |
| **Audio cues** | Critical state changes (errors, loading) have both visual AND VoiceOver announcements |
| **Custom rotors** | Consider adding bookmarks and chapters to the accessibility rotor |

### Current state (already good)
The codebase already has:
- 109 `.accessibility*` modifiers across views
- `.accessibilityElement(children: .combine)` on compound controls
- `.accessibilityAdjustableAction` for the playback scrubber (seek ±15s)
- `.accessibilityHidden(true)` on decorative elements
- `.dynamicTypeSize(.medium ... .accessibility2)` in iPodView
- `@Environment(\.accessibilityReduceMotion)` in 2 views
- `@Environment(\.accessibilityReduceTransparency)` in MainMenuView

### Areas needing improvement (likely gaps)

| View | Likely Issues |
|------|---------------|
| `CuratedChannelsListView` | Search-add button, filter picker tabs, load-more-candidates button, context menu actions |
| `CuratorModeView` → being deleted (Task 1) | N/A |
| `ChannelInfoView` | "Curate" and "Export" buttons (add accessibility labels) |
| `SettingsView` | Kids Mode PIN entry, appearance picker, contribution buttons |
| `AgeGateView` | Math puzzle gate (keyboard interaction for VoiceOver) |
| `KidsMenuView` | PIN entry for exit |
| `ContributionSupportView` | StoreKit purchase buttons |
| `PlaylistDetailView` | Drag-to-reorder rows (accessibility actions for reorder) |
| `SplashView` | Loading animation — marked as decorative |
| `ProceduralVisualizerView` | Should be `.accessibilityHidden(true)` (pure decoration) |

### Specific actions
1. **Audit every view** — make a list of all SwiftUI views and check off each criterion
2. **Run VoiceOver** on device/simulator — navigate through every screen
3. **Test with Dynamic Type** at maximum size — check for truncation/overflow
4. **Test with Reduce Motion** — ensure iPod click wheel animation is disabled
5. **Test with inverted colors** — ensure icons and text remain visible
6. **Add `.accessibilitySortPriority()`** to main content to ensure logical focus order
7. **Add `UIAccessibility.post(notification: .announcement, ...)`** for error/loading state changes that VoiceOver should announce automatically
8. **Test the entire app flow from cold launch** using ONLY VoiceOver — can every feature be accessed without sight?

---

## TASK 14: Output this plan (DONE)

This file is `preparation-for-release.md`.

---

## CONSOLIDATED FILE CHANGE SUMMARY

| Task | Files Created | Files Modified | Files Deleted | Risk |
|------|--------------|----------------|---------------|------|
| 1. Remove CuratorModeView | 1 (`CuratorSearchAddView.swift`) | 1 (`CuratedChannelsListView.swift`) | 2 (`CuratorModeView.swift`, `CuratorController.swift`) | Low |
| 2. Move addAllPartsToReview | 1 (`CurationActions.swift`) | 2 (both curator views) | 0 | Very Low |
| 3. UI tests | 3–5 (`UITests/*.swift`) | 1 (`project.yml`) | 0 | Low |
| 4. Localization catalog | 1 (`Localizable.xcstrings`) | ~35 view files | 0 | Medium |
| 5. News skip → 0 | 0 | 1 (`Channel.swift`) | 0 | Very Low |
| 6. Export this Channel | 0 | 1 (`ChannelInfoView.swift`) | 0 | Low |
| 7. CLI merge tool | 3 (`Tools/merge-curation/`) | 0 | 0 | Low |
| 8. README CI docs | 1 (`README.md`) | 0 | 0 | Very Low |
| 9. .md cleanup | 2 (`README.md`, `AGENTS.md`) | 0 | 6 | Very Low |
| 10. Decompose PlayerVM | ~8 (`*Controller/*Manager.swift`) | 1 (`PlayerViewModel.swift`) | 0 | **HIGH** |
| 11. Siri intents | ~5 (`SiriIntents/`) | 2 (`project.yml`, entitlements) | 0 | Medium |
| 12. Podcast subscriptions | ~4 (`PodcastSubscriptionStore`, `PodcastAddView`, `PodcastSearchService`, migration) | ~8 (rename + integration) | 0 | Medium-High |
| 13. Accessibility audit | 0 | ~15+ view files | 0 | Low |
| **TOTAL** | **~30 files** | **~65 files** | **8 files** | — |

---

## ESTIMATED TIMELINE

| Task | Hours | Can Parallel? |
|------|-------|---------------|
| 1. Remove CuratorModeView | 2 | With Task 2 |
| 2. Move addAllPartsToReview | 1.5 | With Task 1 |
| 3. UI tests | 4 | After Task 1, 2 |
| 4. Localization catalog | 6 | With anything |
| 5. News skip → 0 | 0.5 | With anything |
| 6. Export Channel | 2 | After Task 2 |
| 7. CLI merge tool | 4 | With anything |
| 8. README CI docs | 0.5 | With anything |
| 9. .md cleanup | 0.25 | Anytime |
| 10. Decompose PlayerVM | 8 | After ALL other tasks pass tests |
| 11. Siri intents | 6 | With Task 10 or 12 |
| 12. Podcast subscriptions | 8 | After Task 5 |
| 13. Accessibility audit | 6 | After Tasks 1, 2, 4, 11, 12 |
| **Total** | **~49 hours** | — |

**Recommended execution**: Sequential with parallel clusters:
1. Tasks 4, 5, 7, 8, 9 in parallel (Day 1)
2. Tasks 2, 1, 6 in sequence (Day 2)
3. Task 12 (Day 3–4)
4. Task 3 (Day 4)
5. Tasks 11 + 13 in parallel (Day 5–6)
6. Task 10 (Day 6–7) — with extreme care, after all tests pass on all other changes

---

_END OF PLAN — Review all items before implementation._
