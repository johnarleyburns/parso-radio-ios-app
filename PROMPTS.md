# PROMPTS.md — Agentic Implementation Guide (iOS Radio App) v2

## How to Use

- Run prompts **in order**
- Do NOT skip steps
- Verify compile/build after each step
- Only proceed when acceptance criteria are met
- If the agent drifts, re-send the prompt

---

## Prompt 1 — Project Scaffold

Create a new SwiftUI iOS project called "ParsoRadio" with the following constraints:

- iOS 17+
- SwiftUI only (no UIKit unless absolutely necessary)
- MVVM architecture
- Modular folder structure

Create the full directory structure:

```
ParsoRadio/
├── App/
├── Core/
│   ├── Models/
│   ├── Services/
│   │   ├── API/
│   │   ├── Metadata/
│   │   ├── Storage/
│   │   ├── Playback/
│   │   ├── Download/
│   │   └── License/
│   └── Tests/
├── ViewModels/
├── Views/
└── Utilities/
```

Add placeholder Swift files for each module.

Include:
- App entry point (`ParsoRadioApp.swift`)
- Empty SwiftUI root view
- Basic navigation setup

Do NOT implement logic yet.

**Acceptance criteria:**
- Project compiles
- Folder structure matches exactly
- App launches to a blank screen

---

## Prompt 2 — Core Models

Implement the core data models.

### Track
```swift
struct Track: Codable, Identifiable {
    let id: String
    let source: String
    let title: String
    let artist: String
    let duration: Double
    let streamURL: URL
    let downloadURL: URL?
    var localFilePath: String?
    let license: LicenseType
    let tags: [String]
    let qualityScore: Double

    let rawCreator: String
    let composer: String?           // canonical key: "bach", "chopin", nil if unknown
    let instruments: [String]       // canonical: ["strings"], ["piano"]
    let metadataConfidence: Double  // 0.0–4.0
}
```

### Channel
```swift
struct Channel: Codable, Identifiable {
    let id: String
    let name: String
    let composers: [String]         // canonical keys; empty = match any
    let instruments: [String]       // canonical keys; empty = match any
    let tags: [String]
    var isDownloaded: Bool

    func matches(_ track: Track) -> Bool {
        let composerMatch = composers.isEmpty || composers.contains(track.composer ?? "")
        let instrumentMatch = instruments.isEmpty
            || !instruments.filter { track.instruments.contains($0) }.isEmpty
        return composerMatch && instrumentMatch
    }
}
```

### LicenseType
```swift
enum LicenseType: String, Codable {
    case publicDomain, cc0, ccBy, rejected
}
```

### Channel+Defaults
Add a static `defaults` array with these four predefined channels:

```swift
static let defaults: [Channel] = [
    Channel(id: "bach-vivaldi-strings",
            name: "Bach & Vivaldi — Strings",
            composers: ["bach", "vivaldi"],
            instruments: ["strings"],
            tags: ["classical", "baroque"],
            isDownloaded: false),

    Channel(id: "chopin-rachmaninoff-piano",
            name: "Chopin & Rachmaninoff — Piano",
            composers: ["chopin", "rachmaninoff"],
            instruments: ["piano"],
            tags: ["classical", "romantic"],
            isDownloaded: false),

    Channel(id: "classical",
            name: "Classical",
            composers: [], instruments: [], tags: ["classical"],
            isDownloaded: false),

    Channel(id: "ambient",
            name: "Ambient",
            composers: [], instruments: [], tags: ["ambient"],
            isDownloaded: false),
]
```

Make all models Codable.

**Acceptance criteria:**
- Code compiles
- `Channel.matches()` correctly filters tracks by composer + instrument
- Models serialize/deserialize correctly

---

## Prompt 3 — License Validator

Implement `LicenseValidator.swift`.

```swift
func validate(licenseURL: String?, year: Int?, collection: String?) -> LicenseType
```

Rules (apply in this order):
1. `collection == "musopen"` → `.cc0`
2. `year != nil && year < 1923` → `.publicDomain`
3. `licenseURL` contains `"publicdomain"` → `.publicDomain`
4. `licenseURL` contains `"zero"` → `.cc0`
5. `licenseURL` contains `"licenses/by/"` AND does NOT contain `"by-nc"`, `"by-sa"`, `"by-nd"` → `.ccBy`
6. All else → `.rejected`

**Acceptance criteria:**
- Deterministic output
- No false positives
- Musopen collection items always return `.cc0`
- Pre-1923 items always return `.publicDomain`

---

## Prompt 4 — ComposerMap + InstrumentDetector

Implement `ComposerMap.swift` and `InstrumentDetector.swift` in `Services/Metadata/`.

### ComposerMap.swift

Implement a lookup that normalizes raw creator strings to canonical composer keys.

```swift
struct ComposerMap {
    static let aliases: [String: String] = [
        "bach": "bach", "j.s. bach": "bach", "j. s. bach": "bach",
        "johann sebastian bach": "bach", "bach, johann sebastian": "bach",

        "vivaldi": "vivaldi", "antonio vivaldi": "vivaldi",
        "a. vivaldi": "vivaldi", "vivaldi, antonio": "vivaldi",

        "chopin": "chopin", "f. chopin": "chopin",
        "frederic chopin": "chopin", "frédéric chopin": "chopin",
        "chopin, frederic": "chopin",

        "rachmaninoff": "rachmaninoff", "rachmaninov": "rachmaninoff",
        "s. rachmaninoff": "rachmaninoff", "sergei rachmaninoff": "rachmaninoff",
        "sergei rachmaninov": "rachmaninoff",
    ]

    // For queue expansion when pool is low
    static let similarity: [String: [String]] = [
        "bach":         ["vivaldi", "handel", "telemann", "scarlatti"],
        "vivaldi":      ["bach", "handel", "corelli"],
        "chopin":       ["rachmaninoff", "liszt", "schumann"],
        "rachmaninoff": ["chopin", "tchaikovsky", "scriabin"],
    ]

    static func normalize(_ raw: String) -> String? {
        aliases[raw.lowercased().trimmingCharacters(in: .whitespaces)]
    }
}
```

### InstrumentDetector.swift

Detect instruments from title, subjects, and description using keyword matching.

```swift
struct InstrumentDetector {
    static let stringKeywords = [
        "violin", "cello", "viola", "string quartet", "string orchestra",
        "concerto for strings", "strings", "fiddle", "violoncello",
        "Brandenburg", "Four Seasons"
    ]

    static let pianoKeywords = [
        "piano", "pianoforte", "nocturne", "étude", "etude", "ballade",
        "piano concerto", "piano sonata", "piano trio",
        "prelude for piano", "waltz for piano"
    ]

    // Returns canonical instrument group(s): "strings", "piano"
    // "sonata" alone is NOT piano-specific; "concerto" alone is NOT piano-specific
    func detect(title: String, subjects: [String], description: String?) -> [String]
}
```

**Acceptance criteria:**
- `ComposerMap.normalize("J.S. Bach")` returns `"bach"`
- `ComposerMap.normalize("Rachmaninov")` returns `"rachmaninoff"`
- `InstrumentDetector.detect` returns `["strings"]` for "Brandenburg Concerto No. 3"
- `InstrumentDetector.detect` returns `["piano"]` for "Nocturne Op. 9 No. 2"
- `InstrumentDetector.detect` returns `[]` for an empty title with no subjects

---

## Prompt 5 — MetadataNormalizer

Implement `MetadataNormalizer.swift` in `Services/Metadata/`.

This service converts raw Internet Archive API fields into structured `(composer, instruments, confidence)` output for building a `Track`.

```swift
struct IARawItem {
    let identifier: String
    let title: String?
    let creator: String?
    let subject: [String]
    let description: String?
    let licenseURL: String?
    let year: Int?
    let collection: String?
    let duration: Double?
}

struct NormalizedMetadata {
    let composer: String?
    let instruments: [String]
    let confidence: Double   // 0.0–4.0
}

struct MetadataNormalizer {
    func normalize(_ item: IARawItem) -> NormalizedMetadata
}
```

**Confidence scoring:**
```
confidence =
  (composer resolved via ComposerMap ? 2.0 : 0.0)
  + (instruments non-empty ? 1.0 : 0.0)
  + metadata_quality_score

metadata_quality_score (0.0–1.0):
  has licenseURL:  +0.3
  has subjects:    +0.3
  has duration:    +0.2
  has year:        +0.2
```

Tracks with `confidence < 1.5` are valid for genre channels but excluded from composer/instrument channels.

**Acceptance criteria:**
- A Musopen Bach violin item scores ≥ 3.0
- An item with no creator, no subjects, no licenseurl scores < 1.5
- Composer and instrument resolution matches `ComposerMap` and `InstrumentDetector` outputs

---

## Prompt 6 — InternetArchiveService

Implement `InternetArchiveService.swift` in `Services/API/`.

This is the sole data source. It handles both general queries and Musopen collection queries.

```swift
// Fetch tracks for a composer-based channel
func fetchTracks(composers: [String], instruments: [String]) async throws -> [Track]

// Fetch from Musopen collection (all CC0 — use when bootstrapping offline cache)
func fetchMusopenTracks(composer: String) async throws -> [Track]

// Fetch tracks for a genre/tag-based channel
func fetchTracks(tags: [String]) async throws -> [Track]
```

**URL format:**
```
Base: https://archive.org/advancedsearch.php
Fields to request: identifier, title, creator, subject, licenseurl, description, year, collection
Output: json
Rows: 100
```

**Composer query construction:**
- Use all known aliases from `ComposerMap.aliases` where value matches the target composer
- Combine with OR in the `creator:` field
- Add instrument subjects with OR if instruments is non-empty

**Musopen query:**
```
q=collection:musopen AND creator:"{composerRawName}"
```
Note: do NOT apply `licenseurl` filter to Musopen queries — all Musopen items are CC0 regardless.

**After fetching:**
1. Run each item through `MetadataNormalizer`
2. Run through `LicenseValidator`
3. Discard `.rejected` tracks
4. Build and return `[Track]`

**Streaming URL format:**
```
https://archive.org/download/{identifier}/{filename}
```
(Obtain filename from `https://archive.org/metadata/{identifier}` — fetch the first `.mp3` or `.ogg` file listed)

**Acceptance criteria:**
- Returns valid `Track` objects with `composer`, `instruments`, `metadataConfidence` populated
- Rejected licenses are filtered out
- Network errors throw cleanly
- Musopen items always have `license == .cc0`

---

## Prompt 7 — DatabaseService

Implement `DatabaseService.swift` using SQLite.swift.

**Schema:**

```sql
CREATE TABLE IF NOT EXISTS tracks (
    id TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    duration REAL,
    stream_url TEXT NOT NULL,
    download_url TEXT,
    local_file_path TEXT,
    license_type TEXT NOT NULL,
    tags TEXT NOT NULL DEFAULT '[]',
    quality_score REAL NOT NULL DEFAULT 0,
    raw_creator TEXT NOT NULL DEFAULT '',
    composer TEXT,
    instruments TEXT NOT NULL DEFAULT '[]',
    metadata_confidence REAL NOT NULL DEFAULT 0,
    fetched_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS channels (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    composers TEXT NOT NULL DEFAULT '[]',
    instruments TEXT NOT NULL DEFAULT '[]',
    tags TEXT NOT NULL DEFAULT '[]',
    is_downloaded INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_tracks_composer ON tracks(composer);
CREATE INDEX IF NOT EXISTS idx_tracks_confidence ON tracks(metadata_confidence);
```

**Functions:**
```swift
func saveTracks(_ tracks: [Track])
func fetchTracks(forChannel channel: Channel) -> [Track]   // applies channel.matches()
func markDownloaded(trackID: String, localPath: String)
func fetchDownloadedTracks(forChannel channel: Channel) -> [Track]
func deleteExpiredTracks(olderThan date: Date)
```

In `fetchTracks(forChannel:)`:
- If `channel.composers` is non-empty, add `WHERE composer IN (...)` to the SQL query
- Post-filter in Swift using `channel.matches(track)` for instrument matching

**Acceptance criteria:**
- Data persists between launches
- `fetchTracks(forChannel:)` returns only tracks that pass `channel.matches()`
- Indices make composer queries fast

---

## Prompt 8 — DownloadManager

Implement `DownloadManager.swift`.

```swift
func download(track: Track) async
func prefetchNext(_ tracks: [Track])   // look-ahead 3–5 tracks
```

Features:
- Background `URLSession` downloads
- Save to `Documents/audio/{trackID}.mp3`
- Retry with exponential backoff (3 attempts)
- `@Published var progress: [String: Double]` keyed by track ID
- On completion: call `DatabaseService.markDownloaded()`

**Acceptance criteria:**
- Files saved to sandbox
- Downloads recover from transient failures
- `prefetchNext` does not re-download already-local tracks

---

## Prompt 9 — QueueManager

Implement `QueueManager.swift`.

```swift
func nextTrack(channel: Channel) -> Track?
```

**Algorithm:**
1. Fetch `DatabaseService.fetchTracks(forChannel: channel)` — these already pass `channel.matches()`
2. Filter out tracks in the last-50 play history
3. Sort by `qualityScore * metadataConfidence` (descending), apply weighted random selection
4. Daily deterministic seed: `seed = hash(ISO date string + channel.id)` — produces stable daily order
5. If pool size < 20 and `channel.composers` is non-empty:
   - Expand query using `ComposerMap.similarity` — fetch/load tracks for similar composers that also pass instrument filter
6. If still empty: fall back to any track matching `channel.tags` only

```swift
// History tracking
private var recentlyPlayed: [String] = []   // track IDs, max 50
```

**Acceptance criteria:**
- No repeats within 50 tracks
- Same order for same date + channel
- Falls back gracefully to similar composers then genre tags when pool is small

---

## Prompt 10 — AudioPlayerService

Implement `AudioPlayerService.swift` using `AVPlayer`.

```swift
func play(_ track: Track)
func pause()
func skip()
```

Behavior:
- If `track.localFilePath` exists and file is readable → play from local file
- Otherwise → play from `track.streamURL`

```swift
// AVAudioSession setup
try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
try AVAudioSession.sharedInstance().setActive(true)
```

- Register `MPRemoteCommandCenter` handlers: play, pause, nextTrack
- `@Published var currentTrack: Track?`
- `@Published var isPlaying: Bool`
- Handle interruptions (AVAudioSession interruption notification)

**Acceptance criteria:**
- Reliable playback in foreground and background
- Lock screen controls work
- Handles phone call interruptions
- Falls back to stream when local file missing

---

## Prompt 11 — ViewModels

### ChannelListViewModel
```swift
@MainActor class ChannelListViewModel: ObservableObject {
    @Published var channels: [Channel] = Channel.defaults
    @Published var selectedChannel: Channel?

    func selectChannel(_ channel: Channel)   // triggers prefetch
}
```

### PlayerViewModel
```swift
@MainActor class PlayerViewModel: ObservableObject {
    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false

    func skip()
    func togglePlayPause()
}
```

Use `async/await`; no Combine.

**Acceptance criteria:**
- UI updates correctly on main actor
- `selectChannel` triggers `QueueManager.nextTrack` + `DownloadManager.prefetchNext`
- Clean separation from services

---

## Prompt 12 — SwiftUI UI (iPod Single-Screen)

Implement the UI as a single-screen iPod-style interface.

### Root: `iPodView`
- No `NavigationStack` — the whole app is one screen
- Top: channel name + category label (animated on change)
- Center: `ClickWheel` component (280×280 pt)
- Bottom: now-playing card (track title, artist, license badge, spoken-word progress bar)
- Top-right overlay: ⓘ button opening `AboutView` sheet

### ClickWheel
- Outer ring (280 pt diameter) with 4 zone labels: MENU (top), ⏮ (left), ⏭ (right), ▶/❚❚ (bottom)
- Inner circle (~45% diameter) — decorative, not tappable
- `SpatialTapGesture` determines zone by dominant axis (|dy| vs |dx|)
- `.sensoryFeedback(.impact(.light))` per tap
- Tap zones: MENU → `showChannelSelector`; Left → `playerVM.back()`; Right → `playerVM.skip()`; Bottom → `playerVM.togglePlayPause()`

### ChannelSelectorView (MENU sheet)
- `NavigationStack` inside the sheet
- `List` with `Section` per category (categories sorted A–Z)
- Channels sorted A–Z within each section
- Checkmark (`Image(systemName: "checkmark")`) on current channel
- `Button("Cancel")` in toolbar; channel tap calls `playerVM.load(channel:)` + dismiss

### SplashView (first launch)
- Animated logo on gradient background (auto-dismiss 2.2 s)
- Triggers `TermsView` if `@AppStorage("tosAccepted")` is false

### TermsView (first-launch gate)
- `fullScreenCover` + `interactiveDismissDisabled(true)`
- Scrollable EULA body; sentinel `Color.clear.onAppear` marks scroll completion
- Checkbox: "I have read and agree…"
- "Agree & Continue" enabled only when scrolled to bottom AND checkbox ticked
- On agree: `UserDefaults.standard.set(true, forKey: "tosAccepted")`

### AboutView (ⓘ sheet)
- App icon gradient + version + "© 2026 Parso Consulting"
- Full privacy policy text

**Acceptance criteria:**
- Renders on iPhone 15 Pro and iPhone SE (3rd gen)
- No truncated text
- ClickWheel tap zones correctly dispatch all four actions
- TermsView cannot be dismissed without agreement
- AboutView accessible from ⓘ at all times

---

## Prompt 13 — Offline System

Implement offline mode.

### Cache bootstrap (run at first launch + every 24h)
1. For each channel in `Channel.defaults`:
   - If `channel.composers` is non-empty: call `InternetArchiveService.fetchMusopenTracks()` for each composer (CC0, offline-safe)
   - Also call `InternetArchiveService.fetchTracks(composers:instruments:)` for general IA results
   - Save all to `DatabaseService`
   - Download top 50 by `metadataConfidence` via `DownloadManager`

### Playback buffer
- Maintain 3–5 tracks downloaded ahead of the current position
- `DownloadManager.prefetchNext()` called after each `nextTrack()`

### Offline detection
- Check `NWPathMonitor` for connectivity
- Offline: serve from `DatabaseService.fetchDownloadedTracks(forChannel:)` only
- Online: serve downloaded if available, stream otherwise + continue prefetching

**Acceptance criteria:**
- 45-minute playback in airplane mode after initial cache build
- No interruptions during offline playback
- New tracks downloaded in background when back online

---

## Prompt 14 — Final Integration

Integrate all modules.

Wire:
- `ChannelListViewModel` → `QueueManager` → `AudioPlayerService`
- `QueueManager` → `DatabaseService`
- `DownloadManager` → `DatabaseService` (mark downloaded)
- `InternetArchiveService` → `MetadataNormalizer` → `LicenseValidator` → `DatabaseService`

Add logging via `Logger` at:
- Track fetch start/complete
- License rejections (log rejected license URL)
- Download start/complete/failure
- Queue expansion (when falling back to similar composers)

Test:
- Cold start with empty cache → fetches + plays within 10s
- Switch channels → queue rebuilds correctly
- Airplane mode → no crash, plays cached tracks
- Channel with no matching tracks → graceful fallback to genre tags

**Acceptance criteria:**
- No crashes
- Smooth playback across channel switches
- Composer channels return only matching composer+instrument tracks
- Confidence threshold (< 1.5) correctly excludes low-quality metadata tracks from composer channels

---

## Final Notes

- Prefer simplicity over abstraction
- Do not add FMA or ccMixter integrations — both are unusable for this app's use case
- Rachmaninoff: only fetch pre-1928 compositions; validate against the allowed list before saving
- "sonata" and "concerto" alone do NOT imply piano — always require additional piano keywords
- Keep modules loosely coupled
- MetadataNormalizer runs on a background actor; never on MainActor
