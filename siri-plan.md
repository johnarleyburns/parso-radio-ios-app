# Siri Intents — Three-Tier Implementation Plan

## Current state

The app uses iOS 17 `AppIntents` with 3 intents (`PlayLorewaveIntent`, `PlayChannelIntent`, `PlayPodcastIntent`), all with `openAppWhenRun = true` which forces foreground launch. Entity queries provide channels via `ChannelEntity` / `PodcastEntity`. An `AppIntentBridge` singleton bridges intents to `PlayerViewModel`.

**Gaps**: No intent donations, no Siri-specific launch UX, always foregrounds the app, no entity fuzzy-matching beyond what Siri NLP provides, zero test coverage for the intents layer.

---

## Tier 1: Intent donations + entity resolution improvements

**Files changed/created:**
- `ParsoRadio/Intents/IntentDonationManager.swift` **(new)**
- `ParsoRadio/Intents/LorewaveIntents.swift` — add `searchAliases` to entities
- `ParsoRadio/Intents/ChannelEntity.swift` — add `searchAliases` field, improve `displayRepresentation`
- `ParsoRadio/Intents/AppIntentBridge.swift` — add donation call after loadChannel
- `ParsoRadio/ViewModels/PlayerViewModel.swift` — call donation after channel load/restore
- `ParsoRadio/Core/Tests/IntentsTests.swift` **(new)**

### 1a: Intent donations

After every explicit channel load (user action or Siri), donate the intent interaction so Siri learns patterns and suggests shortcuts proactively.

```swift
// IntentDonationManager.swift — new file
import AppIntents
import Intents

@MainActor
enum IntentDonationManager {
    static func donateChannel(_ channel: Channel) {
        let entity = ChannelEntity(id: channel.id, displayName: channel.name,
                                    searchAliases: aliasesFor(channel))
        let intent = PlayChannelIntent()
        intent.channel = entity
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate()
    }

    static func donatePodcast(_ channel: Channel) {
        let entity = PodcastEntity(id: channel.id, displayName: channel.name,
                                    searchAliases: aliasesFor(channel))
        let intent = PlayPodcastIntent()
        intent.podcast = entity
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate()
    }

    static func donateResume(_ channel: Channel) {
        let interaction = INInteraction(intent: PlayLorewaveIntent(), response: nil)
        interaction.donate()
    }

    private static func aliasesFor(_ channel: Channel) -> [String] {
        // Strip parentheticals: "NPR 1A (Public Affairs)" -> "NPR 1A"
        var aliases: [String] = []
        let base = channel.name
        if let parenIdx = base.firstIndex(of: "(") {
            let stripped = base[..<parenIdx].trimmingCharacters(in: .whitespaces)
            if stripped != base { aliases.append(stripped) }
        }
        return aliases
    }
}
```

**Integration points — `AppIntentBridge.swift`:**

Add donation after `loadChannel` and `resumePlayback`:

```swift
func loadChannel(_ channel: Channel) async {
    guard !KidsModeController.shared.isEnabled, let vm = playerVM else { return }
    await vm.load(channel: channel, autoPlay: true)
    IntentDonationManager.donateChannel(channel)
    if channel.category == "Podcasts" {
        IntentDonationManager.donatePodcast(channel)
    }
}

func resumePlayback() async {
    // ... existing logic ...
    await vm.restoreLastSession(fallbackChannel: channel, autoPlay: true)
    IntentDonationManager.donateResume(channel)
}
```

**Integration point — `PlayerViewModel.load(channel:)`** (around line 454):
Add donation call after `UserDefaults.standard.set(visited, forKey: "visitedChannelIds")`:
```swift
IntentDonationManager.donateChannel(channel)
if channel.category == "Podcasts" {
    IntentDonationManager.donatePodcast(channel)
}
```

### 1b: Entity resolution — search aliases

Add `searchAliases` to both `ChannelEntity` and `PodcastEntity` to improve Siri's NLP matching against channel names with parentheticals or abbreviations.

```swift
// ChannelEntity.swift — updated
struct ChannelEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Channel")
    static let defaultQuery = ChannelEntityQuery()

    let id: String
    let displayName: String
    let searchAliases: [String]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: searchAliases.isEmpty ? nil : searchAliases.joined(separator: ", ")
        )
    }
}
```

Same pattern for `PodcastEntity`. The `ChannelEntityQuery` and `PodcastEntityQuery` now include aliases:

```swift
// ChannelEntityQuery
func suggestedEntities() async throws -> [ChannelEntity] {
    let visited = UserDefaults.standard.stringArray(forKey: "visitedChannelIds") ?? []
    let ordered = visited.compactMap { id in Channel.defaults.first { $0.id == id } }
        + Channel.defaults.filter { !visited.contains($0.id) }
    return Array(ordered.prefix(40)).flatMap { ch -> [ChannelEntity] in
        let aliases = aliasesFor(ch)
        return [ChannelEntity(id: ch.id, displayName: ch.name, searchAliases: aliases)]
    }
}
```

### 1c: Tests — `IntentsTests.swift`

| Test | What it verifies |
|------|-----------------|
| `testDonateChannelAfterLoad` | Donation manager is called with correct entity after channel load |
| `testDonatePodcastForPodcastCategory` | Podcast donation fires only for Podcasts category |
| `testDonateResumeAfterRestore` | Resume donation fires after restoreLastSession |
| `testEntityQueryByIdentifier` | `entities(for:)` returns correct entity for known ID |
| `testEntityQueryByIdentifierMissing` | `entities(for:)` returns empty for unknown ID |
| `testSuggestedEntitiesOrderVisitedFirst` | Visited channels appear before unvisited |
| `testSuggestedEntitiesCapped` | `suggestedEntities()` returns ≤40 |
| `testPodcastEntityQueryOnlyReturnsPodcasts` | Podcast query filters to Podcasts category |
| `testPodcastEntityQueryDecodesCorrectly` | Podcast entities map to correct channels |
| `testAliasesStrippedParenthetical` | "NPR 1A (Public Affairs)" alias is "NPR 1A" |
| `testKidsModeBlocksIntentBridge` | Bridge refuses to load when Kids Mode is on |
| `testIntentBridgeWithNilPlayerVM` | Bridge handles missing playerVM gracefully |

---

## Tier 2: Siri launch UX (skip splash, direct-to-player)

**Files changed:**
- `ParsoRadio/Intents/AppIntentBridge.swift` — set `siri.pendingChannelId` before loading
- `ParsoRadio/App/ParsoRadioApp.swift` — skip splash when launched from Siri
- `ParsoRadio/Views/iPodView.swift` — detect Siri-launched channel, avoid double-restore
- `ParsoRadio/Core/Tests/SiriLaunchTests.swift` **(new)**

### 2a: Signal Siri launch before loading

In `AppIntentBridge`, set a UserDefaults flag BEFORE calling PlayerViewModel so the app's startup can detect the pending Siri command:

```swift
func loadChannel(_ channel: Channel) async {
    guard !KidsModeController.shared.isEnabled, let vm = playerVM else { return }
    UserDefaults.standard.set(channel.id, forKey: "siri.pendingChannelId")
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "siri.pendingTimestamp")
    await vm.load(channel: channel, autoPlay: true)
    IntentDonationManager.donateChannel(channel)
    if channel.category == "Podcasts" { IntentDonationManager.donatePodcast(channel) }
}

func resumePlayback() async {
    guard !KidsModeController.shared.isEnabled, let vm = playerVM else { return }
    let lastId = UserDefaults.standard.string(forKey: "lastChannelId") ?? "guitar-classical"
    let channel = Channel.defaults.first { $0.id == lastId }
        ?? Channel.defaults.first { $0.id == "guitar-classical" }
        ?? Channel.defaults[0]
    UserDefaults.standard.set(channel.id, forKey: "siri.pendingChannelId")
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "siri.pendingTimestamp")
    await vm.restoreLastSession(fallbackChannel: channel, autoPlay: true)
    IntentDonationManager.donateResume(channel)
}
```

### 2b: Skip splash screen

In `ParsoRadioApp.swift`, compute `showSplash` initial value from the Siri pending flag:

```swift
@State private var showSplash: Bool = {
    if UserDefaults.standard.string(forKey: "siri.pendingChannelId") != nil {
        return false
    }
    return true
}()
```

This means when Siri launches the app (intent's `perform()` already called `loadChannel`), the splash is skipped immediately. The iPodView appears at `opacity: 1` with audio already loading.

### 2c: Avoid double-restore in iPodView.task

The normal `iPodView.task` calls `restoreLastSession(fallbackChannel:autoPlay:)`. When launched from Siri, the intent already triggered a channel load. Detect this and skip:

```swift
.task {
    await playlistVM.loadPlaylists()
    UserDefaults.standard.removeObject(forKey: "wasPlayingOnQuit")

    // If a Siri/Shortcut intent already triggered a channel load, skip the
    // normal restore — the load is already in progress.
    if let pendingId = UserDefaults.standard.string(forKey: "siri.pendingChannelId") {
        UserDefaults.standard.removeObject(forKey: "siri.pendingChannelId")
        UserDefaults.standard.removeObject(forKey: "siri.pendingTimestamp")
        // Channel load already kicked off by the intent. Just present the
        // player view with whatever is loading.
        return
    }

    if kids.isEnabled {
        // ... existing kids mode restore ...
    } else {
        await playerVM.restoreLastSession(fallbackChannel: pendingChannel, autoPlay: false)
    }
    // ... wheel help ...
}
```

### 2d: Stale timestamp guard

If the pending timestamp is older than 60 seconds (app backgrounded and returned, or a crash), clear the stale pending flag before checking:

```swift
private func clearStaleSiriPending() {
    guard let ts = UserDefaults.standard.object(forKey: "siri.pendingTimestamp") as? TimeInterval else { return }
    let age = Date().timeIntervalSince1970 - ts
    if age > 60 {
        UserDefaults.standard.removeObject(forKey: "siri.pendingChannelId")
        UserDefaults.standard.removeObject(forKey: "siri.pendingTimestamp")
    }
}
```

### 2e: Tests — `SiriLaunchTests.swift`

| Test | What it verifies |
|------|-----------------|
| `testBridgeSetsPendingOnLoadChannel` | `siri.pendingChannelId` is set before loadChannel |
| `testBridgeSetsPendingOnResume` | `siri.pendingChannelId` is set before resumePlayback |
| `testBridgeSetsPendingTimestamp` | `siri.pendingTimestamp` is set alongside the channel ID |
| `testSplashFlagWhenPending` | `showSplash` initializes to false when pending exists |
| `testSplashFlagWhenNoPending` | `showSplash` initializes to true when no pending exists |
| `testPendingClearedOnRead` | iPodView.task clears the pending flag after reading |
| `testStalePendingCleared` | Pending flag older than 60s is treated as expired |
| `testNoDoubleRestoreWhenPending` | iPodView.task skips restoreLastSession when pending exists |
| `testKidsModeSkipsPending` | Kids Mode enabled skips pending restores appropriately |

---

## Tier 3: Background/cold-start intent handling

**Goal**: Handle Siri intents without bringing the app to the foreground.

**Files changed/created:**
- `ParsoRadio/Intents/LorewaveIntents.swift` — remove `openAppWhenRun`, add process detection
- `ParsoRadio/IntentsExtension/` — new extension target directory **(new)**
- `project.yml` — new `LorewaveIntents` extension target
- `ParsoRadio/IntentsExtension/LorewaveIntentsExtension.entitlements` **(new)**
- `ParsoRadio/IntentsExtension/IntentHandler.swift` **(new)** — handles ext-process execution
- `ParsoRadio/IntentsExtension/Info.plist` **(new)**
- `ParsoRadio/Core/Tests/BackgroundIntentTests.swift` **(new)**

### Architecture

```
┌──────────────────────────────────────────────────────┐
│  SIRI / SPOTLIGHT / SHORTCUTS APP                    │
│  Invokes PlayChannelIntent                           │
└────────────────────┬─────────────────────────────────┘
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
   App IS RUNNING          App NOT RUNNING
   (fg or suspended)       (cold start)
          │                     │
          ▼                     ▼
   Intent executes         Extension process
   IN-PROCESS              handles intent
   (playerVM exists)       (no playerVM)
          │                     │
          ▼                     ▼
   loadChannel()          Write command to
   starts playback        App Group UserDefaults
   immediately                  │
          │                     ▼
          ▼              Return .result()
   Return .result()      → Siri dialog ends
   → Audio plays                │
   in background          ┌─────┴──────────┐
                          ▼                 ▼
                   App NOT running    App IS running
                   (killed):          (suspended):
                   User must tap      observe App Group
                   result to open     → execute pending
                          │                 │
                          ▼                 ▼
                   App opens,        loadChannel()
                   reads pending,    starts playback
                   starts playback
```

### 3a: Remove `openAppWhenRun`

In `LorewaveIntents.swift`, change all three intents from `openAppWhenRun = true` to `openAppWhenRun = false`. This means:
- **When app IS running**: Intent executes in-process, audio starts without foregrounding.
- **When app IS NOT running**: iOS briefly launches the app process for intent handling. If the process includes the App struct + PlayerViewModel, playback can start. If not (extension-style process), the intent stores the command and completes.

### 3b: Hybrid intent handler

Add process detection in intent `perform()`:

```swift
struct PlayChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Channel"
    static let description = IntentDescription("Start playing a specific channel on Lorewave.")
    static let openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$channel) on Lorewave")
    }

    @Parameter(title: "Channel")
    var channel: ChannelEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard !KidsModeController.shared.isEnabled else {
            throw IntentError.kidsModeActive
        }
        guard let ch = Channel.defaults.first(where: { $0.id == channel.id }) else {
            throw IntentError.channelNotFound(channel.displayName)
        }

        // In-process: app is running, PlayerViewModel exists
        if let vm = AppIntentBridge.shared.playerVM {
            UserDefaults.standard.set(ch.id, forKey: "siri.pendingChannelId")
            await vm.load(channel: ch, autoPlay: true)
            IntentDonationManager.donateChannel(ch)
            if ch.category == "Podcasts" { IntentDonationManager.donatePodcast(ch) }
            return .result()
        }

        // Extension process: store command for the main app to pick up
        storePendingCommand(channelId: ch.id)
        return .result()
    }

    private func storePendingCommand(channelId: String) {
        UserDefaults.standard.set(channelId, forKey: "siri.pendingChannelId")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "siri.pendingTimestamp")
    }
}
```

### 3c: App Group communication (for extension process)

When the intent runs in an extension process, writing to `UserDefaults.standard` goes to the extension's sandbox, NOT the main app. We need App Groups.

Add App Group capability to both the main app and the extension target. Use `UserDefaults(suiteName: "group.guru.parso.ios-radio-app")` for cross-process communication.

```swift
// Shared constant in AppIntentBridge.swift
enum AppGroup {
    static let suiteName = "group.guru.parso.ios-radio-app"
}

extension UserDefaults {
    static var appGroup: UserDefaults {
        UserDefaults(suiteName: AppGroup.suiteName) ?? .standard
    }
}
```

### 3d: Main app reads pending commands

In `ParsoRadioApp.swift`, observe scene phase changes to pick up commands written by the extension:

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .active {
        handleSiriPendingCommand()
        if tosAccepted, !showSplash,
           !KidsModeController.shared.isEnabled { contributions.evaluate() }
    }
}

private func handleSiriPendingCommand() {
    guard let channelId = UserDefaults.appGroup.string(forKey: "siri.pendingChannelId") else { return }
    guard let ts = UserDefaults.appGroup.object(forKey: "siri.pendingTimestamp") as? TimeInterval,
          Date().timeIntervalSince1970 - ts < 60 else {
        UserDefaults.appGroup.removeObject(forKey: "siri.pendingChannelId")
        UserDefaults.appGroup.removeObject(forKey: "siri.pendingTimestamp")
        return
    }
    UserDefaults.appGroup.removeObject(forKey: "siri.pendingChannelId")
    UserDefaults.appGroup.removeObject(forKey: "siri.pendingTimestamp")

    guard let ch = Channel.defaults.first(where: { $0.id == channelId }),
          !KidsModeController.shared.isEnabled else { return }

    Task { @MainActor in
        await playerVM.load(channel: ch, autoPlay: true)
    }
}
```

### 3e: Extension target configuration

Add to `project.yml`:

```yaml
LorewaveIntents:
  type: app-extension
  platform: iOS
  deploymentTarget: "17.0"
  sources:
    - path: ParsoRadio/IntentsExtension
  dependencies:
    - target: ParsoMusic
  settings:
    base:
      GENERATE_INFOPLIST_FILE: YES
      PRODUCT_BUNDLE_IDENTIFIER: guru.parso.ios-radio-app.intents
      INFOPLIST_KEY_CFBundleDisplayName: Lorewave Intents
      INFOPLIST_KEY_NSExtension:
        NSExtensionPrincipalClass: "$(PRODUCT_MODULE_NAME).IntentHandler"
      MARKETING_VERSION: "2.0.1"
      CURRENT_PROJECT_VERSION: "1"
  entitlements:
    path: ParsoRadio/IntentsExtension/LorewaveIntentsExtension.entitlements
```

Entitlements for the extension:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.siri</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.guru.parso.ios-radio-app</string>
    </array>
</dict>
</plist>
```

Update main app entitlements to include App Groups:
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.guru.parso.ios-radio-app</string>
</array>
```

### 3f: Extension intent handler

`ParsoRadio/IntentsExtension/IntentHandler.swift`:
```swift
import Intents

class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any { self }
}

extension IntentHandler: PlayLorewaveIntentHandling {
    func handle(intent: PlayLorewaveIntent) async -> PlayLorewaveIntentResponse {
        let lastId = UserDefaults.appGroup.string(forKey: "lastChannelId") ?? "guitar-classical"
        UserDefaults.appGroup.set(lastId, forKey: "siri.pendingChannelId")
        UserDefaults.appGroup.set(Date().timeIntervalSince1970, forKey: "siri.pendingTimestamp")
        return PlayLorewaveIntentResponse(code: .continueInApp, userActivity: nil)
    }
}

extension IntentHandler: PlayChannelIntentHandling {
    func handle(intent: PlayChannelIntent) async -> PlayChannelIntentResponse {
        guard let channel = intent.channel else {
            return PlayChannelIntentResponse(code: .failure, userActivity: nil)
        }
        UserDefaults.appGroup.set(channel.identifier, forKey: "siri.pendingChannelId")
        UserDefaults.appGroup.set(Date().timeIntervalSince1970, forKey: "siri.pendingTimestamp")
        return PlayChannelIntentResponse(code: .continueInApp, userActivity: nil)
    }
}
```

### 3g: Tests — `BackgroundIntentTests.swift`

| Test | What it verifies |
|------|-----------------|
| `testIntentWithoutOpenAppWhenRun` | `openAppWhenRun` is false on all intents |
| `testPerformInProcessWithPlayerVM` | When playerVM exists, intent executes directly |
| `testPerformWithoutPlayerVM` | When playerVM is nil, stores pending command gracefully |
| `testAppGroupUserDefaultsWrite` | Pending command is written to App Group UserDefaults |
| `testAppGroupUserDefaultsRead` | Main app reads and clears pending command |
| `testStalePendingCommandIgnored` | Pending command >60s old is ignored |
| `testAppGroupSuiteNameConsistent` | Suite name matches between extension and main app |
| `testHandlePendingOnForeground` | scenePhase handler picks up pending command |
| `testKidsModeBlocksPendingExecution` | Kids Mode prevents pending command execution |
| `testPendingCommandCleanedUpAfterExecution` | Pending keys removed after execution |

---

## Test infrastructure

### New test files

1. **`ParsoRadio/Core/Tests/IntentsTests.swift`** — Tier 1 tests
2. **`ParsoRadio/Core/Tests/SiriLaunchTests.swift`** — Tier 2 tests
3. **`ParsoRadio/Core/Tests/BackgroundIntentTests.swift`** — Tier 3 tests

### Test patterns

All tests use the existing patterns:
- `DatabaseService(path: ":memory:")` for DB isolation
- `@MainActor` on test classes that touch PlayerViewModel
- `FakeAudioEngine` for deterministic audio control
- `UserDefaults(suiteName:)` for UserDefaults isolation
- `@testable import ParsoMusic`

### UserDefaults isolation

Tests that modify UserDefaults keys like `siri.pendingChannelId`, `lastChannelId`, `visitedChannelIds` must use isolated suites to avoid state leakage:

```swift
let defaults = UserDefaults(suiteName: "IntentsTests")!
defaults.removePersistentDomain(forName: "IntentsTests")
```

For App Group tests:
```swift
let appGroupDefaults = UserDefaults(suiteName: "group.guru.parso.ios-radio-app.test")!
```

---

## Build & verify

```bash
# Regenerate project after adding files and targets
xcodegen generate

# Build the main app + extension
xcodebuild -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' build

# Run unit tests (all new test files)
xcodebuild -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' \
  test -only-testing:ParsoMusicTests

# Manual verification on device:
# 1. Use Shortcuts app to run "Play Channel" — verify app opens and plays
# 2. "Hey Siri, Play Classical Guitar on Lorewave" — verify app opens and plays
# 3. "Hey Siri, Play Lorewave" — verify app opens and resumes
# 4. After several uses, check if Siri suggests shortcuts in Spotlight
```

---

## File manifest

| File | Action | Tier |
|------|--------|------|
| `ParsoRadio/Intents/IntentDonationManager.swift` | **Create** | 1 |
| `ParsoRadio/Intents/LorewaveIntents.swift` | Modify | 1, 3 |
| `ParsoRadio/Intents/ChannelEntity.swift` | Modify | 1 |
| `ParsoRadio/Intents/AppIntentBridge.swift` | Modify | 1, 2, 3 |
| `ParsoRadio/App/ParsoRadioApp.swift` | Modify | 2, 3 |
| `ParsoRadio/Views/iPodView.swift` | Modify | 2 |
| `ParsoRadio/IntentsExtension/IntentHandler.swift` | **Create** | 3 |
| `ParsoRadio/IntentsExtension/LorewaveIntentsExtension.entitlements` | **Create** | 3 |
| `ParsoRadio/IntentsExtension/Info.plist` | **Create** | 3 |
| `project.yml` | Modify | 3 |
| `ParsoMusic.entitlements` | Modify | 3 |
| `ParsoRadio/Core/Tests/IntentsTests.swift` | **Create** | 1 |
| `ParsoRadio/Core/Tests/SiriLaunchTests.swift` | **Create** | 2 |
| `ParsoRadio/Core/Tests/BackgroundIntentTests.swift` | **Create** | 3 |
