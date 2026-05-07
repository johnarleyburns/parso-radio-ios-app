# iOS Offline Creative Commons Radio App – Technical Design Document (v2)

## 1. Overview
Fully on-device iOS radio app:
- No backend
- Offline-first
- Streams + downloads legally safe music (Public Domain, CC0, CC-BY)
- Minimal "old-fashioned radio" UX
- Composer + instrument channels (Bach/Vivaldi strings, Chopin/Rachmaninoff piano)

Target: Swift + SwiftUI, iOS 17+

---

## 2. Architecture Overview

### Pattern
- MVVM (Model-View-ViewModel)
- Service-oriented data layer
- Local persistence via SQLite (SQLite.swift)

### High-Level Flow
1. Fetch metadata from Internet Archive (including Musopen collection)
2. Normalize composer names + detect instruments
3. Score track-channel relevance
4. Filter rejected licenses
5. Store locally
6. Build radio queue filtered by channel's composer/instrument criteria
7. Stream or play local file

### Data Source Strategy
- **Only source: Internet Archive Advanced Search API**
  - General classical/PD recordings via creator/subject/licenseurl queries
  - Musopen CC0 catalog via `collection:musopen` filter (no separate API)
- **FMA:** dropped — API permanently shut down
- **ccMixter:** dropped — no classical repertoire

---

## 3. Directory Structure

```
ParsoRadio/
├── App/
│   ├── ParsoRadioApp.swift
│   ├── AppDelegate.swift
│
├── Core/
│   ├── Models/
│   │   ├── Track.swift
│   │   ├── Channel.swift
│   │   ├── License.swift
│   │
│   ├── Services/
│   │   ├── API/
│   │   │   ├── InternetArchiveService.swift   ← handles both general + Musopen collection
│   │   │
│   │   ├── Metadata/
│   │   │   ├── MetadataNormalizer.swift        ← composer normalization + instrument detection
│   │   │   ├── ComposerMap.swift               ← raw→canonical lookup + expansion map
│   │   │   ├── InstrumentDetector.swift        ← keyword matching + confidence scoring
│   │   │
│   │   ├── Storage/
│   │   │   ├── DatabaseService.swift
│   │   │   ├── FileStorageService.swift
│   │   │
│   │   ├── Playback/
│   │   │   ├── AudioPlayerService.swift
│   │   │   ├── QueueManager.swift
│   │   │
│   │   ├── Download/
│   │   │   ├── DownloadManager.swift
│   │   │   ├── CacheManager.swift
│   │   │
│   │   ├── License/
│   │   │   ├── LicenseValidator.swift
│   │
│   ├── Tests/
│
├── ViewModels/
│   ├── ChannelListViewModel.swift
│   ├── PlayerViewModel.swift
│
├── Views/
│   ├── ChannelListView.swift
│   ├── PlayerView.swift
│   ├── NowPlayingView.swift
│
├── Utilities/
│   ├── Logger.swift
│   ├── Extensions.swift
│
└── Resources/
    ├── Assets.xcassets
```

---

## 4. Core Models

### Track.swift
```swift
struct Track: Codable, Identifiable {
    let id: String
    let source: String              // always "internet_archive"
    let title: String
    let artist: String
    let duration: Double
    let streamURL: URL
    let downloadURL: URL?
    var localFilePath: String?
    let license: LicenseType
    let tags: [String]
    let qualityScore: Double        // 0.0–1.0, from metadata completeness

    // Composer + instrument fields
    let rawCreator: String          // unmodified creator field from IA API
    let composer: String?           // canonical key: "bach", "chopin", nil if unknown
    let instruments: [String]       // canonical: ["strings"], ["piano"], ["strings","violin"]

    // Scoring
    let metadataConfidence: Double  // composer_match*2 + instrument_match + metadata_quality
}
```

### Channel.swift
```swift
struct Channel: Codable, Identifiable {
    let id: String
    let name: String
    let composers: [String]         // canonical keys; empty = any composer
    let instruments: [String]       // canonical keys; empty = any instrument
    let tags: [String]              // genre fallback for non-composer channels
    var isDownloaded: Bool

    // A track matches this channel when:
    // 1. composers is empty, OR track.composer ∈ self.composers
    // 2. instruments is empty, OR track.instruments ∩ self.instruments is non-empty
    func matches(_ track: Track) -> Bool {
        let composerMatch = composers.isEmpty || composers.contains(track.composer ?? "")
        let instrumentMatch = instruments.isEmpty || !instruments.filter { track.instruments.contains($0) }.isEmpty
        return composerMatch && instrumentMatch
    }
}
```

### License.swift
```swift
enum LicenseType: String, Codable {
    case publicDomain
    case cc0
    case ccBy
    case rejected
}
```

### Predefined Channels (Channel+Defaults.swift)
```swift
static let defaults: [Channel] = [
    Channel(id: "bach-vivaldi-strings",
            name: "Bach & Vivaldi — Strings",
            composers: ["bach", "vivaldi"],
            instruments: ["strings"],
            tags: ["classical", "baroque"]),

    Channel(id: "chopin-rachmaninoff-piano",
            name: "Chopin & Rachmaninoff — Piano",
            composers: ["chopin", "rachmaninoff"],
            instruments: ["piano"],
            tags: ["classical", "romantic"]),

    Channel(id: "classical",
            name: "Classical",
            composers: [],
            instruments: [],
            tags: ["classical"]),

    Channel(id: "ambient",
            name: "Ambient",
            composers: [],
            instruments: [],
            tags: ["ambient"]),
]
```

---

## 5. Services

### 5.1 InternetArchiveService
Single service; handles both general search and Musopen collection queries.

```swift
// General composer+instrument query
func fetchTracks(composers: [String], instruments: [String]) async throws -> [Track]

// Musopen collection (CC0 guaranteed)
func fetchMusopenTracks(composer: String) async throws -> [Track]

// Generic tag-based query for genre channels
func fetchTracks(tags: [String]) async throws -> [Track]
```

**Query construction:**

```
# Composer search — IA creator field has many variants; query all known aliases
https://archive.org/advancedsearch.php
  ?q=mediatype:audio
    AND (creator:"Johann Sebastian Bach" OR creator:"J.S. Bach" OR creator:"Bach, Johann Sebastian")
    AND (subject:"strings" OR subject:"violin" OR subject:"cello" OR subject:"string quartet")
    AND (licenseurl:*publicdomain* OR licenseurl:*zero* OR licenseurl:*by/*)
  &fl[]=identifier,title,creator,subject,licenseurl,description,year
  &output=json
  &rows=100

# Musopen collection (guaranteed CC0 — skip licenseurl filter)
https://archive.org/advancedsearch.php
  ?q=collection:musopen AND creator:"Chopin"
  &fl[]=identifier,title,creator,subject,licenseurl
  &output=json&rows=100

# Stream URL for a file:
https://archive.org/download/{identifier}/{filename}.mp3
# Download URL (same):
https://archive.org/download/{identifier}/{filename}.mp3
```

**Metadata note:** Many IA items lack `licenseurl`. For items with `year < 1923`, treat as public domain regardless. For items with `collection:musopen`, treat as CC0 regardless.

---

### 5.2 MetadataNormalizer
Converts raw IA API fields into structured Track composer/instrument data.

```swift
struct MetadataNormalizer {
    func normalize(iaItem: IARawItem) -> (composer: String?, instruments: [String], confidence: Double)
}
```

**Confidence score:**
```
confidence = composer_match_score + instrument_match_score + metadata_quality_score

composer_match_score:  2.0 if canonical composer resolved, 0.0 otherwise
instrument_match_score: 1.0 if ≥1 instrument detected, 0.0 otherwise
metadata_quality_score: 0.0–1.0 based on field completeness
  - has licenseurl: +0.3
  - has subject tags: +0.3
  - has duration: +0.2
  - has year: +0.2
```

Tracks with `confidence < 1.5` are excluded from composer/instrument channels (may still appear in genre channels).

---

### 5.3 ComposerMap
Dictionary-based normalization + expansion map.

```swift
// Raw → canonical
let composerAliases: [String: String] = [
    "bach": "bach", "j.s. bach": "bach", "j. s. bach": "bach",
    "johann sebastian bach": "bach", "bach, johann sebastian": "bach",

    "vivaldi": "vivaldi", "antonio vivaldi": "vivaldi", "a. vivaldi": "vivaldi",
    "vivaldi, antonio": "vivaldi",

    "chopin": "chopin", "f. chopin": "chopin", "frederic chopin": "chopin",
    "frédéric chopin": "chopin", "chopin, frederic": "chopin",

    "rachmaninoff": "rachmaninoff", "rachmaninov": "rachmaninoff",
    "s. rachmaninoff": "rachmaninoff", "sergei rachmaninoff": "rachmaninoff",
    "sergei rachmaninov": "rachmaninoff",
]

// Expansion map: if user plays a channel, also consider nearby composers
let composerSimilarity: [String: [String]] = [
    "bach":         ["vivaldi", "handel", "telemann", "scarlatti"],
    "vivaldi":      ["bach", "handel", "corelli"],
    "chopin":       ["rachmaninoff", "liszt", "schumann"],
    "rachmaninoff": ["chopin", "tchaikovsky", "scriabin"],
]
```

The expansion map is used by QueueManager when a channel's primary pool runs low: expand to similar composers before falling back to unfiltered genre tags.

---

### 5.4 InstrumentDetector
Keyword matching against title, subject tags, and description.

```swift
struct InstrumentDetector {
    func detect(title: String, subjects: [String], description: String?) -> [String]
}
```

**Keyword groups:**
```swift
let stringKeywords = [
    "violin", "cello", "viola", "string quartet", "string orchestra",
    "concerto for strings", "strings", "fiddle", "violoncello",
    "Brandenburg", "Four Seasons"          // high-confidence Baroque titles
]

let pianoKeywords = [
    "piano", "pianoforte", "nocturne", "étude", "etude", "ballade",
    "piano concerto", "piano sonata", "piano trio",
    "prelude for piano", "waltz for piano"
    // Note: "sonata" alone is NOT piano-specific (violin sonatas exist)
    // Note: "concerto" alone is NOT piano-specific
]
```

Detection returns canonical groups: `"strings"` or `"piano"`. A track may have both.

---

### 5.5 LicenseValidator
```swift
func validate(licenseURL: String?, year: Int?, collection: String?) -> LicenseType
```

Rules (in priority order):
1. `collection == "musopen"` → `.cc0`
2. `year != nil && year < 1923` → `.publicDomain`
3. `licenseURL` contains `"publicdomain"` → `.publicDomain`
4. `licenseURL` contains `"zero"` → `.cc0`
5. `licenseURL` contains `"licenses/by/"` (not `by-nc`, `by-sa`, `by-nd`) → `.ccBy`
6. All else → `.rejected`

---

### 5.6 DatabaseService
SQLite-backed persistence.

```swift
func saveTracks(_ tracks: [Track])
func fetchTracks(forChannel: Channel) -> [Track]   // applies Channel.matches()
func markDownloaded(trackID: String, localPath: String)
func fetchDownloadedTracks(forChannel: Channel) -> [Track]
```

**Schema:**
```sql
CREATE TABLE tracks (
    id TEXT PRIMARY KEY,
    source TEXT,
    title TEXT,
    artist TEXT,
    duration REAL,
    stream_url TEXT,
    download_url TEXT,
    local_file_path TEXT,
    license_type TEXT,
    tags TEXT,              -- JSON array
    quality_score REAL,
    raw_creator TEXT,
    composer TEXT,          -- nullable canonical key
    instruments TEXT,       -- JSON array
    metadata_confidence REAL,
    fetched_at INTEGER      -- unix timestamp
);

CREATE TABLE channels (
    id TEXT PRIMARY KEY,
    name TEXT,
    composers TEXT,         -- JSON array
    instruments TEXT,       -- JSON array
    tags TEXT,              -- JSON array
    is_downloaded INTEGER
);

CREATE INDEX idx_tracks_composer ON tracks(composer);
CREATE INDEX idx_tracks_confidence ON tracks(metadata_confidence);
```

---

### 5.7 FileStorageService
- Save downloaded audio to app sandbox (`Documents/audio/`)
- Manage file paths
- LRU eviction when cache exceeds configurable limit (default 2 GB)

---

### 5.8 DownloadManager
```swift
func download(track: Track) async
func prefetchNext(tracks: [Track])   // look-ahead 3–5 tracks
```

Features:
- Background URLSession downloads
- Retry with exponential backoff
- Progress tracking via `@Published`

---

### 5.9 QueueManager
```swift
func nextTrack(channel: Channel) -> Track?
```

**Algorithm:**
1. Load all locally cached tracks matching `channel.matches(track)`
2. Sort by: not in last-50 history → weighted by `qualityScore * metadataConfidence`
3. Daily deterministic shuffle: `seed = hash(ISO date string + channel.id)`
4. If pool is smaller than 20 tracks, expand query to `composerSimilarity` neighbors
5. If still empty, fall back to channel's `tags`-only filter

---

### 5.10 AudioPlayerService
```swift
func play(_ track: Track)
func pause()
func skip()
```

- Prefer `localFilePath` over `streamURL`
- Configure `AVAudioSession` for background playback (category `.playback`)
- Handle interruptions (phone calls, other audio apps)
- Expose `currentTime` and `duration` as `@Published`

---

## 6. ViewModels

### ChannelListViewModel
- Loads predefined channels (`Channel.defaults`)
- Exposes download state per channel
- Triggers background prefetch on channel selection

### PlayerViewModel
- `currentTrack: Track?` — `@Published`
- `playbackState: PlaybackState` — `@Published`
- `skip()` — calls QueueManager then AudioPlayerService

---

## 7. UI Design — iPod Single-Screen

### Design Principles
- Single-screen: no navigation stack, no separate PlayerView
- Skeuomorphic iPod click-wheel as primary control surface
- MENU button opens channel selector sheet; no other navigation
- Large tap targets (ring zones ≥ 44pt each)
- High contrast; minimal chrome

### Screen Layout (iPodView)
```
┌─────────────────────────────────────────┐
│  Channel Name          [ⓘ]             │
│                                         │
│         ╔═══════════════╗              │
│         ║     MENU      ║              │
│         ║  ◀◀  ●  ▶▶  ║              │
│         ║    ▶/❚❚       ║              │
│         ╚═══════════════╝              │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │ 🎵  Track Title                │   │
│  │     Artist · License badge      │   │
│  │     ████████░░░░░ 2:07 / 4:23  │   │  ← spoken-word only
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### ClickWheel (SpatialTapGesture hit zones)
- Outer ring divided into 4 tap zones by dominant axis (|dy| vs |dx|):
  - Top → MENU: open ChannelSelectorView sheet
  - Left → Back: rewind 15 s (spoken word) / restart track (music)
  - Right → Forward: skip to next track
  - Bottom → Play/Pause: toggle playback
- Center circle: no action (decorative)
- `.sensoryFeedback(.impact(.light))` on each tap

### ChannelSelectorView (MENU sheet)
- Grouped by category (sorted A–Z)
- Channels sorted A–Z within each category
- Checkmark on currently playing channel
- Selecting a channel: loads it immediately + dismisses sheet

### AboutView (ⓘ sheet)
- App icon + version + "© 2026 Parso Consulting"
- Full privacy policy text (no data collected; local position only)

### SplashView + TermsView (first launch)
- Animated logo splash (auto-dismiss after 2.2 s)
- TermsView fullScreenCover shown once if tosAccepted == false
- Scroll-to-bottom + checkbox required before "Agree & Continue"
- Stored via @AppStorage("tosAccepted")

---

## 8. Offline Mode

### Look-Ahead Buffer
- Maintain 3–5 downloaded tracks ahead of current position

### Channel Download
- Target: 50–150 tracks per channel cached locally
- Prioritize Musopen CC0 tracks (no attribution required) when building initial offline cache

---

## 9. Playback Flow

1. User taps channel
2. `ChannelListViewModel` selects channel, triggers prefetch
3. `QueueManager.nextTrack(channel:)` returns first track
4. `DownloadManager.prefetchNext()` queues next 3–5
5. `AudioPlayerService.play(track)` — local file if exists, else stream URL

---

## 10. Background Audio

- Enable `audio` background mode in entitlements (already in `project.yml`)
- `AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)`
- Register `MPRemoteCommandCenter` handlers (play, pause, skip)

---

## 11. Storage Strategy

- Max cache: configurable (default 2 GB)
- LRU eviction (oldest play timestamp)
- Preserve tracks with `localFilePath` that are in any active channel's pool

---

## 12. Error Handling

- Skip broken stream URLs
- Retry failed downloads (3× with backoff)
- Fall back to stream if local file is corrupted
- Log all errors via `Logger`

---

## 13. Performance

- All network calls: `async/await`
- IA API fetches at launch + every 24h in background
- SQLite queries on background actor
- Lazy loading in SwiftUI lists

---

## 14. Implementation Notes

- Swift Concurrency (`async/await`) throughout
- SwiftUI only; no UIKit
- AVFoundation for playback
- SQLite.swift for persistence
- `@MainActor` on ViewModels
- `MetadataNormalizer` runs on a background actor

---

## 15. Future Extensions

- Composer similarity "expand channel" feature (tap to include Handel when in Bach channel)
- Favorites system
- AirPlay
- CarPlay integration

---

## 16. Summary

This design enables:
- Fully offline radio playback
- Legal compliance (PD + CC0 + CC-BY; Rachmaninoff scoped to pre-1928 works)
- Composer + instrument channels via metadata normalization + confidence scoring
- Simple UX with no exposed complexity

Ready for direct implementation by an agentic coding system.
