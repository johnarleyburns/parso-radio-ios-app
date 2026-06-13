# REARCHITECTURE_PLAN.md — Lorewave / Parso Radio

_A phased design document for an agentic coding system. Read this top-to-bottom before making any change. Then execute one phase at a time, in order, stopping at each verification gate._

---

## 0. Read first: how to use this document

You are modifying a **mature, shipping iOS app** (bundle `guru.parso.ios-radio-app`, marketing version 2.0.1) with ~180 Swift files, ~38 unit-test suites, integration tests that hit real Internet Archive APIs, and a CI pipeline that auto-ships to TestFlight on every push to `main`. This is not a greenfield project. **Behavior-preserving, incremental, test-gated change is mandatory.** A clever rewrite that breaks one invariant can ship a broken build to real users.

Rules for the whole job:

1. **Execute phases in order.** Each phase ends at a **verification gate**. Do not start phase N+1 until phase N's gate is green.
2. **Every phase must leave the app building and all unit tests passing.** No phase may be left half-done across a commit boundary.
3. **Additive before subtractive.** When replacing a mechanism, first introduce the new one alongside the old (both compiling, old still authoritative), prove equivalence with tests, then remove the old. Never delete the old path and the call sites in the same step.
4. **Respect the existing invariants in `AGENTS.md` and `README.md`.** They are reproduced in §2 below. Several are non-obvious and were hard-won bug fixes. Re-read §2 before each phase.
5. **After adding/removing/renaming any `.swift` file, run `xcodegen generate`.** Files are not auto-discovered. The build will silently exclude new files until you do.
6. **Run the unit-test suite locally before every commit** (a pre-push hook enforces this anyway):
   ```bash
   xcodegen generate
   xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     -only-testing:ParsoMusicTests
   ```
7. **Do not touch the curation architecture** except where a phase explicitly says so. See §2.1 — it is the single most regression-prone area in the codebase.
8. **Commit per phase**, with the commit message prefixed `rearch(phaseN):`. Keep diffs reviewable.

---

## 1. Goal and non-goals

### 1.1 The thesis

Lorewave correctly ships as **one app** spanning music, audiobooks, podcasts, lectures, and ambient. That is the right product decision: the value is the curation layer over open-culture audio, and the cross-genre mix (channels, daily picks, playlists that can mix types) _is_ the product. Splitting into three apps would destroy the differentiator and triple the maintenance surface for a solo developer.

The problem is **not** that it's one app. The problem is that "one app" is currently implemented as **one undifferentiated blob**:

- Content-type behavior is decided by scattered `if channel.category == "Lectures"` / `if channel.contentType == .spokenWord` / `if channel.feedURL != nil` string checks in ~15 files. There is **no single source of truth** for "how does an audiobook behave vs. a music track."
- `PlayerViewModel` is a **2,337-line God object** (the README says so explicitly) that owns transport, queueing, shuffle/repeat, playlists, book navigation, variable speed, sleep timer, bookmarks, recently-played, chapters, autosave, session restore, recommendations, and curator audition.
- The player UI hardcodes a couple of `contentType` branches inline rather than composing controls from a declared capability set.

### 1.2 What this plan does

Three things, in service of your "do one thing well" instinct — applied to the **internal seams**, not the app boundary:

1. **Separation.** Introduce a first-class **`MediaKind` + `PlaybackBehavior`** domain model as the _single source of truth_ for per-type behavior, route every scattered branch through it, then decompose the `PlayerViewModel` God object into focused, independently testable controllers behind a thin facade.

2. **A decisive UI overhaul, not a touch-up.** Replace the parallel, overlapping navigation surfaces with **one** modern, Apple-HIG-native structure: a bottom **`TabView`** (Listen · Library · Search), a persistent **mini-player** docked above the tab bar, and a single full-screen **Now Playing** sheet that **composes its controls from the declared `behavior`** (music → shuffle/queue; long-form → scrub/speed/sleep/chapters/resume; ambient → minimal transport). Fewer screens, one navigation model, less code, every screen reading as stock iOS. This is as aggressive as the engineering work — see §4.3 for the target design and the principles below.

3. **Modular escape hatch.** Re-draw the file/module boundaries (local Swift packages) so that **if** future data ever justifies a standalone app, spinning one out is a days-long job, not a rewrite. You build from data later; you keep optionality now.

### 1.2.1 Design principles (the bar every UI phase is held to)

- **One navigation model.** A single `TabView`-rooted structure with a `NavigationStack` per tab. No second parallel way to get anywhere. The current state — a 1,700-line grid `HomeView`, a separate drill-down `MainMenuView`, and a separate click-wheel `iPodView` all acting as co-equal entry points — is the central KISS violation and is eliminated.
- **Apple-HIG-native, not bespoke.** Standard `TabView`, `NavigationStack`, `.searchable`, `.toolbar`, `ContentUnavailableView`, system materials, SF Symbols, large titles where the platform expects them, inline titles where it doesn't. Do not invent custom chrome that fights the system. If Apple Music / Apple Podcasts does it a certain way, default to that way.
- **The Apple-media-app spine.** Persistent mini-player above the tab bar → tap to expand into a full-screen Now Playing sheet → swipe/chevron to dismiss back to the mini-player. This is the one interaction pattern users already know; adopt it exactly.
- **KISS engineering.** Delete dead and duplicate paths rather than wrapping them in flags. One source of truth for sections/categories. No `UserDefaults`-gated "experimental" alternates of the new design — the new design ships as the design. (Flags are still fine for genuine kill-switches on risky _backend_ behavior, never to hide finished UI.)
- **Accessibility & adaptivity are acceptance criteria, not polish.** Dynamic Type, Dark Mode, Reduce Transparency (opaque fallbacks), and VoiceOver labels must work on every new surface, verified before a phase's gate is green.
- **Aggressive target, disciplined path.** The _end state_ is bold and replaces what's there. The _route_ is still additive-before-subtractive and test-gated (§0) — because this auto-ships to TestFlight on every push. "Aggressive" describes the destination, never the willingness to break a gate.

### 1.3 Explicit non-goals (do NOT do these)

- **Do NOT split the app into multiple App Store products.** No new app targets that ship separately. The escape hatch (Phase 6) is about _module boundaries_, not shipped binaries.
- **Do NOT change the curation data model or its DB-is-source-of-truth contract.** (§2.1)
- **Do NOT change network/IA query behavior, the isolation-stamp mechanism, or `ia_queries.json`.**
- **Do NOT alter the favorites data model** (`Favorite.swift`). It already matches its spec (`FavoriteKind` = track/book/episode/lecture + `ResumePoint`). Phase 1 will _reuse_ its logic, not replace it.
- **Do NOT introduce new third-party dependencies** beyond the existing SQLite.swift without explicit instruction.
- **Do NOT hide the new design behind a flag.** The modern `TabView`/Now-Playing structure is _the_ UI after Phase 5, on by default for all users. Feature flags are permitted only as kill-switches for risky backend behavior, never to make the finished new design optional.

> **On the iPod click wheel (`iPodView.swift`):** it is explicitly **in scope for change** under this revision. It is a skeuomorphic, non-HIG, parallel navigation system and is the single biggest KISS violation in the app. It is **demoted from a co-equal navigation entry point to, at most, an optional "Retro" skin of the Now Playing screen** reachable from Settings — it no longer roots navigation, and the modern surfaces never depend on it. Fully retiring it is a clean, encouraged follow-up. (This is the one brand-identity call in the plan; it is made deliberately in favor of the cleaner design per the explicit instruction to be aggressive. If the owner wants it gone entirely rather than preserved as a Settings skin, that is a strictly smaller change — delete `iPodView.swift` and its entry point.)

---

## 2. Guardrails: invariants you must not break

These are reproduced and consolidated from `AGENTS.md` and `README.md`. Treat them as hard constraints.

### 2.1 Curation architecture (most regression-prone — DO NOT REGRESS)

```
INSTALL/UPDATE (one-time): per-channel JSON → import to SQLite curation table
                           (only if DB has zero verdicts for that channel)
RUNTIME (ongoing):  Approve/Reject → setCuration() → SQLite curation table
                    → reload() → in-memory LiveCurationStore
                    → QueueManager reads from in-memory pool
SHARE (one-time):   Export DB verdicts → JSON/CSV;  Import JSON → setCuration() → reload()
```

NEVER:
- Write to per-channel JSON files from verdict methods.
- Add JSON/bundled fallback to `LiveCurationStore.pool(for:)` — it is DB-only.
- Delete curation rows in `evictOldTracks()` (verdicts survive track eviction).
- Delete curation rows without a channel filter in `pruneChannelTracks()`.

### 2.2 Concurrency & reactivity invariants

- All ViewModels are `@MainActor`.
- All DB access goes through a serial `DispatchQueue`, bridged to async via `withCheckedContinuation`.
- `currentChannel` on `PlayerViewModel` IS `@Published`. Do not revert it to a plain `var`.
- `playbackContextToken` aborts stale `playTrack` calls during rapid skip/back. Preserve it.
- `failedAuditionTrackId` is set BEFORE `currentTrack` is cleared on failure. Curator views read `currentTrack?.id ?? failedAuditionTrackId`.
- AVPlayer's periodic time observer fires on a 0.25s timer, NOT on audio progress. A stalled item fires `onTimeUpdate(seconds: 0.0)` repeatedly. `confirmPlayback` is guarded by `seconds > 0` — zero ticks must NOT disarm the stall watchdog (20s `stallTimeout`).
- `currentPosition` is throttled to ~2×/sec to limit cascading recomputation. Keep the throttle.

### 2.3 Struct/init ordering pitfalls (compile-breaking if reordered)

- `Track` memberwise init: `partNumber` before `parentIdentifier`.
- `Channel` init: `category` before `icon`, `preferredSource` before `feedURL`.

### 2.4 Build & test invariants

- New `.swift` files require `xcodegen generate` before they're compiled.
- XCTest runs in alphabetical order; tests sharing singletons (`LiveCurationStore`, `CustomChannelsStore`) can leak state — keep them independent.
- DB tests use `try DatabaseService(path: ":memory:")`.
- `QueueManager` tests inject a custom `manifestPool` closure.
- `FakeAudioEngine` provides deterministic playback for tests.
- IA service tests use `MockURLProtocol` (static handler, not parallel-safe).

### 2.5 Instant-resume & podcast invariants

- `load(channel:)` checks saved position BEFORE the network; if the track is in DB and still approved, it plays immediately (`isLoading = false`) while a detached task refreshes the pool.
- Podcast/news channels (`feedURL != nil`) play sequentially newest-first with 30-day dedup, from 0:00 (RSS ToS compliance), unless `startOffsetSeconds` is set.

---

## 3. Current-state map (so you know what you're touching)

### 3.1 The content-type model today (the thing to fix)

Three overlapping, stringly-typed signals decide behavior, with no single owner:

| Signal | Type | Where | Values |
|---|---|---|---|
| `Channel.contentType` | `enum ContentType` | `Core/Models/Channel.swift` | `.music`, `.spokenWord`, `.ambientLoop` |
| `Channel.category` | `String` | `Core/Models/Channel.swift` | `For You`, `Lectures`, `Podcasts`, `Curated`, `Curated Books`, `Audiobooks`, `Ambient` |
| `Channel.preferredSource` / `Track.source` | `String?` | models | `internet_archive`, `oxford_lectures`, `podcast`, `nps`, `freesound`, `fma` |
| `Channel.feedURL` | `String?` | `Channel.swift` | RSS feed ⇒ podcast |
| `Channel.iaQueryEntry` | computed | `Channel.swift` | non-nil ⇒ pure-Lucene "radio" channel |

`spokenWord` **conflates** audiobooks, lectures, and podcasts even though they want different transport (audiobooks: chapters + resume + book-skip; podcasts: sequential newest-first, no chapter list; lectures: random radio). The code recovers the distinction by re-checking `category`/`source`/`feedURL` ad hoc in each call site.

There is already a **nascent, correct version of the abstraction** living in `Core/Models/Favorite.swift`:

```swift
enum ContentTypeHint { case musicTrack, audiobook, podcastEpisode, lecture }
extension Track { func resolveContentType(channel: Channel?) -> ContentTypeHint { ... } }
```

**Phase 1 promotes this idea to a first-class, app-wide `MediaKind` and attaches a `PlaybackBehavior` to it.** The favorites `ContentTypeHint` becomes a thin shim over `MediaKind` (or is replaced by it) so logic lives in one place.

### 3.2 Scattered branching inventory (the refactor targets)

Approximate count of content-type / category branches per file (grep of `contentType|spokenWord|ambientLoop|category ==|isCuratedCategory|feedURL`):

```
PlayerViewModel.swift ........ 37   ← God object; Phase 2 + Phase 3
HomeView.swift ............... 15   ← 1,700 lines; Phase 5
ChannelInfoView.swift ........ 11   ← Phase 4/5
QueueManager.swift ............ 6   ← Phase 2 (behavior-driven selection)
MainMenuView.swift ............ 4   ← Phase 5
ChannelListView.swift ......... 3
iPodView.swift ................ 3   ← click wheel; behavior reads only, minimal touch
LocalFileImportService.swift .. 4
CustomChannelsStore.swift ..... 3
(others) ...................... 1–2 each
```

### 3.3 PlayerViewModel responsibilities (the God object to decompose)

From the method map, `PlayerViewModel` (2,337 lines) currently owns all of:

1. **Transport**: `load`, `togglePlayPause`, `skip`, `seek`, `seekBy`, `back`, `goToPreviousTrack`, `playTrack`.
2. **Queue/advance**: `advanceToNext`, `advancePlaylist`, `playPreviousTrack`, `refreshChannelPool`, `prefetchNextURL`, `randomAlbumTrack`.
3. **Shuffle/repeat**: `toggleShuffle`, `toggleRepeat`.
4. **Whole book/album**: `resolveItemParts`, `addEntireItemToPlaylist`, `playEntireCurrentItem`, `playAlbumTracks`, `playSequentialItem`, `probeCurrentTrack`.
5. **Playlist playback**: `loadPlaylist`, `savedPlaylistResume`, `shufflePlaylist`, `resumePlaylist`, `playlistKey`.
6. **Book navigation**: `skipToNextBook`, `skipToPreviousBook`.
7. **Variable speed**: `setPlaybackRate`.
8. **Sleep timer**: `startSleepTimer`, `setSleepAtEndOfTrack`, `cancelSleepTimer`.
9. **Bookmarks**: `addBookmarkAtCurrentPosition`, `deleteBookmark`, `seekToBookmark`, `fetchCurrentItemChapters`.
10. **Recently played / history**: `recentlyPlayedTracks`, `playRecentTrack`, `removeFromRecentlyPlayed`, `clearRecentlyPlayed`, `clearListeningHistory`.
11. **Autosave**: `saveAutosaveForCurrentTrack`, `deleteAutosaveForTrack`, `autosavePosition`.
12. **Session restore**: `persistSession`, `restoreLastSession`, `migratedChannelId`.
13. **Recommendations**: `fetchRecommendations`.
14. **Audition (curator)**: `auditionTrack`, `stopAudition`, `stopAuditionWithoutRestore`, `failedAuditionTrackId`.
15. **Stall handling**: `handleStallIfNeeded`, `handleLoadFailure`, `classify`.
16. **Kids mode**: `enterKidsMode`, `assertKidsModeInvariant`.

Phase 3 extracts groups 7–14 into standalone `@MainActor` controllers, leaving `PlayerViewModel` as a facade over transport/queue/stall (groups 1–3, 15) that delegates the rest.

### 3.4 Build/module shape today

- One app target `ParsoMusic` (sources under `ParsoRadio/`), one app-extension `LorewaveIntents`, three test targets. XcodeGen (`project.yml`). No local Swift packages yet — everything is one module. DI container `AppDependencies` already exists (good foundation), though many services are still `.shared` singletons.

---

## 4. Target architecture

### 4.1 Layered modules (end state after Phase 6)

```
┌──────────────────────────────────────────────────────────────┐
│ App shell  (ParsoMusic target)                                │
│   ParsoRadioApp, AppDependencies wiring, HomeView, iPodView,  │
│   KidsHomeView, splash/terms/age-gate, Intents bridge         │
└───────────────┬───────────────┬───────────────┬──────────────┘
        depends on        depends on       depends on
┌───────────────▼──┐ ┌──────────▼─────┐ ┌────────▼──────────┐
│ MusicFeature     │ │ SpokenFeature  │ │ AmbientFeature    │
│ music now-playing│ │ audiobook +    │ │ loop/nature       │
│ surface, shuffle │ │ podcast +      │ │ minimal transport │
│ /queue UI        │ │ lecture UI:    │ │                   │
│                  │ │ chapters,speed,│ │                   │
│                  │ │ sleep, resume  │ │                   │
└───────────────┬──┘ └──────────┬─────┘ └────────┬──────────┘
                └─────────┬──────┴────────────────┘
                ┌─────────▼───────────────────────────────────┐
                │ ParsoCore  (local SPM package)               │
                │  Models (Channel, Track, MediaKind,          │
                │   PlaybackBehavior, Favorite, Playlist…)     │
                │  PlaybackEngine (AudioPlayerService,         │
                │   QueueManager, controllers)                 │
                │  Services (IA, FMA, Podcast RSS, Oxford,     │
                │   Download, DatabaseService, Curation,       │
                │   Metadata, FavoritesStore)                  │
                └──────────────────────────────────────────────┘
```

`ParsoCore` is the shared brain. Each `*Feature` package owns the **type-specific UI surface and any type-specific orchestration**, and depends only on `ParsoCore`. The app shell composes them. **No Feature package imports another Feature package** — that property is exactly what makes a future standalone app cheap (drop the other Features, keep Core + one Feature).

> Phases 1–5 can be done **without** creating SPM packages — they work inside the single module by folder convention. Phase 6 is where folders become enforced package boundaries. Doing the logic separation first (1–5) and the physical separation last (6) keeps every step low-risk.

### 4.2 The core abstraction: `MediaKind` + `PlaybackBehavior`

The keystone. Defined once in `ParsoCore`, derived from the channel/track, and consulted everywhere a type decision is made.

```swift
// Core/Models/MediaKind.swift  (NEW in Phase 1)

/// The single source of truth for "what kind of thing is this and how does it behave."
public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case music        // tracks; shuffle pool; replay model
    case audiobook    // multi-part works; chapters; resume; book-skip
    case podcast      // episodes; sequential newest-first; resume
    case lecture      // talks; radio-style random; resume optional
    case ambient      // single looping soundscape; minimal transport
}

/// Declarative capability set. UI composes itself from this; the queue/transport
/// layer reads it. Replaces scattered `if category == ...` checks.
public struct PlaybackBehavior: Equatable, Sendable {
    public enum QueueStyle: Sendable { case shuffledPool, sequentialNewestFirst, sequentialInOrder, singleLoop }

    public let queueStyle: QueueStyle
    public let allowsShuffleToggle: Bool      // music: yes; book/podcast: no
    public let showsScrubbableProgress: Bool  // long-form: yes; radio music: no
    public let supportsChapters: Bool         // audiobook: yes
    public let supportsSpeedControl: Bool     // spoken: yes; music/ambient: no
    public let supportsSleepTimer: Bool       // spoken + ambient: yes
    public let persistsResumePosition: Bool   // spoken: yes; radio music: no
    public let supportsBookSkip: Bool         // audiobook: yes (next/prev book)
    public let supportsBookmarks: Bool        // spoken: yes
    public let startsAtZeroAlways: Bool       // podcast RSS ToS: yes
}

public extension MediaKind {
    var behavior: PlaybackBehavior {
        switch self {
        case .music:
            return .init(queueStyle: .shuffledPool, allowsShuffleToggle: true,
                         showsScrubbableProgress: false, supportsChapters: false,
                         supportsSpeedControl: false, supportsSleepTimer: false,
                         persistsResumePosition: false, supportsBookSkip: false,
                         supportsBookmarks: false, startsAtZeroAlways: false)
        case .audiobook:
            return .init(queueStyle: .sequentialInOrder, allowsShuffleToggle: false,
                         showsScrubbableProgress: true, supportsChapters: true,
                         supportsSpeedControl: true, supportsSleepTimer: true,
                         persistsResumePosition: true, supportsBookSkip: true,
                         supportsBookmarks: true, startsAtZeroAlways: false)
        case .podcast:
            return .init(queueStyle: .sequentialNewestFirst, allowsShuffleToggle: false,
                         showsScrubbableProgress: true, supportsChapters: false,
                         supportsSpeedControl: true, supportsSleepTimer: true,
                         persistsResumePosition: true, supportsBookSkip: false,
                         supportsBookmarks: true, startsAtZeroAlways: true)
        case .lecture:
            return .init(queueStyle: .shuffledPool, allowsShuffleToggle: false,
                         showsScrubbableProgress: true, supportsChapters: false,
                         supportsSpeedControl: true, supportsSleepTimer: true,
                         persistsResumePosition: true, supportsBookSkip: false,
                         supportsBookmarks: true, startsAtZeroAlways: false)
        case .ambient:
            return .init(queueStyle: .singleLoop, allowsShuffleToggle: false,
                         showsScrubbableProgress: false, supportsChapters: false,
                         supportsSpeedControl: false, supportsSleepTimer: true,
                         persistsResumePosition: false, supportsBookSkip: false,
                         supportsBookmarks: false, startsAtZeroAlways: false)
        }
    }
}
```

**Derivation (one function, the ONLY place the legacy signals are read):**

```swift
// Core/Models/MediaKind+Resolve.swift  (NEW in Phase 1)
public extension Channel {
    var mediaKind: MediaKind {
        if contentType == .ambientLoop || category == "Ambient" { return .ambient }
        if feedURL != nil || preferredSource == "podcast" { return .podcast }
        if preferredSource == "oxford_lectures" || category == "Lectures" { return .lecture }
        if category == "Audiobooks" || category == "Curated Books" { return .audiobook }
        if contentType == .spokenWord {
            // spokenWord not otherwise classified → treat as audiobook (multi-part, resume)
            return .audiobook
        }
        return .music
    }
    var behavior: PlaybackBehavior { mediaKind.behavior }
}
```

This is the **derivation seam**. Legacy `category`/`contentType`/`feedURL` strings remain on `Channel` (don't rip them out — `ia_queries.json`, isolation stamps, and styling still use `category`). But **behavioral** decisions stop reading them directly and read `channel.mediaKind` / `channel.behavior` instead.

> Note the existing `QueueManager.usesShuffle` logic (`shuffleMode || iaQueryEntry != nil || category == "Lectures"`) must be preserved in spirit: `iaQueryEntry != nil` "radio" channels shuffle their pool regardless of kind. Encode this by having the queue layer combine `behavior.queueStyle` with the radio flag (see Phase 2.3), not by losing it.

### 4.3 Target UI: the modern, HIG-native structure (end state after Phase 5)

This replaces `HomeView` (grid sprawl), `MainMenuView` (drill-down), and `iPodView` (click-wheel) as parallel entry points with **one** structure. There is exactly one way to navigate.

```
┌──────────────────────────────────────────────────────────┐
│  RootTabView                                             │
│                                                          │
│   ┌─ Tab: Listen ──────────┐  ← curated discovery        │
│   │  NavigationStack         │     (the old Home content, │
│   │   • For You row          │      decomposed & calmed)  │
│   │   • Sections grouped by  │                            │
│   │     MediaKind:           │                            │
│   │       Music · Books ·    │                            │
│   │       Podcasts ·         │                            │
│   │       Lectures · Ambient │                            │
│   │   → channel → Now Playing│                            │
│   └──────────────────────────┘                            │
│   ┌─ Tab: Library ─────────┐  ← the user's own stuff      │
│   │   • Playlists            │                            │
│   │   • Favorites            │                            │
│   │   • Recently Played      │                            │
│   │   • Downloads            │                            │
│   └──────────────────────────┘                            │
│   ┌─ Tab: Search ──────────┐  ← full-screen .searchable   │
│   │   results → Now Playing │                            │
│   └──────────────────────────┘                            │
│                                                          │
│  ╔══════════════════════════════════════════════════╗   │
│  ║  Mini-player (persistent, above tab bar)          ║   │ ← always docked
│  ║  artwork · title · play/pause · (tap → expand)    ║   │   when audio loaded
│  ╚══════════════════════════════════════════════════╝   │
│  [ Listen ]      [ Library ]      [ Search ]             │ ← standard tab bar
└──────────────────────────────────────────────────────────┘
            │ tap mini-player ▼ expands
┌──────────────────────────────────────────────────────────┐
│  NowPlayingSheet (full-screen, swipe-down to dismiss)    │
│   large artwork · title/creator · license/source badges  │
│   ── controls composed from channel.behavior ──          │
│   ScrubBar?  TransportControls  ShuffleToggle?           │
│   SpeedControl?  SleepTimer?  ChapterButton?             │
│   BookSkip?  BookmarkButton?                             │
└──────────────────────────────────────────────────────────┘
```

Rules that make this HIG-native and KISS:

- **`RootTabView` is the only root.** `ParsoRadioApp` shows `RootTabView` (or `KidsHomeView` when Kids Mode is on) — nothing else. No alternate roots.
- **Three tabs, SF Symbol each:** Listen (`square.stack` / `sparkles`), Library (`music.note.list`), Search (`magnifyingglass`). Settings is a `.toolbar` gear in Listen, not a tab (KISS — it's infrequent).
- **Mini-player is a single shared component** rendered once by `RootTabView` as an overlay/`safeAreaInset` above the tab bar, visible whenever `currentTrack != nil`, on every tab. It honors Reduce Transparency with an opaque fallback (reuse the existing mini-player styling from `MainMenuView`/`HomeView`, consolidated into one `MiniPlayer.swift`).
- **Now Playing is one full-screen sheet**, presented from the mini-player, dismissed by swipe-down or a chevron. Its body is the behavior-composed control stack from §4.2 / Phase 4 — no per-type view code.
- **Library groups the user's own content**; Listen groups curated/browse content. Favorites and Recently Played move **into Library** (today they're scattered/nested). One obvious home for "my stuff."
- **Sections derive from one source.** The Listen tab's section list (which `MediaKind` groups, in what order, with what icon/label) comes from a single `LibrarySectioning` definition consumed by both Listen and Search facets — never duplicated `categoryOrder` arrays.
- **Kids Mode** keeps its own simple `List`-based home but adopts the same `NowPlayingSheet` + `MiniPlayer` (it already uses `NowPlayingScreen`), so there is one Now-Playing implementation app-wide.

---

## 5. The phased plan

Each phase: **scope → steps → verification gate → acceptance criteria.** Do not cross a gate that isn't green.

---

### PHASE 0 — Baseline & safety net

**Scope:** Capture a known-good baseline so every later phase can prove "no behavior changed."

**Steps:**
1. `xcodegen generate` then run the full unit suite; record pass/fail counts. If anything is already failing on `main`, STOP and report — do not build on a red baseline.
2. Run the integration suite once (network) and record results; flaky network tests are acceptable to note but not to "fix" here.
3. Add a characterization test file `Core/Tests/MediaKindBaselineTests.swift` that asserts, for **every** channel in `Channel.defaults`, the _current_ effective behavior as observed through existing code paths:
   - which channels shuffle (`QueueManager.usesShuffle(channel:shuffleMode:false)`),
   - which are sequential (`feedURL != nil`),
   - which show the progress bar (`contentType == .spokenWord` per `PlayerView`),
   - which persist resume position.
   These assertions encode today's behavior as the oracle for Phases 1–2.

**Verification gate:** Full unit suite green, including the new baseline test, with no production code changed.

**Acceptance:** A committed baseline test that will fail loudly if Phase 1/2 changes any channel's effective behavior.

---

### PHASE 1 — Introduce `MediaKind` + `PlaybackBehavior` (purely additive)

**Scope:** Add the new domain model. Change **no** call sites yet. Nothing behaves differently.

**Steps:**
1. Create `Core/Models/MediaKind.swift` and `Core/Models/MediaKind+Resolve.swift` exactly as in §4.2.
2. Re-express `Favorite.swift`'s `ContentTypeHint` / `resolveContentType` in terms of `MediaKind` so the favorites mapping and the new model can't drift:
   - Add `Track.mediaKind(in channel: Channel?) -> MediaKind` that mirrors the existing `resolveContentType` rules (podcast source → `.podcast`, oxford → `.lecture`, Audiobooks/Curated Books category → `.audiobook`, parentIdentifier + spokenWord → `.audiobook`, else `.music`).
   - Map `MediaKind → FavoriteKind` (`music→track`, `audiobook→book`, `podcast→episode`, `lecture→lecture`, `ambient→track`) and have `Favorite`'s logic delegate to it. Keep `FavoriteKind` and the favorites DB schema unchanged.
3. `xcodegen generate`.
4. Add `Core/Tests/MediaKindTests.swift`:
   - For every `Channel.defaults` entry, assert `channel.mediaKind` equals the expected kind (write the expected table explicitly — this is the contract).
   - Assert the `MediaKind → behavior` table matches §4.2 field-by-field.
   - Assert `channel.behavior` agrees with the Phase 0 baseline oracle: e.g. every channel where baseline said "shuffles" has `behavior.queueStyle == .shuffledPool` OR is a radio (`iaQueryEntry != nil`) channel; every `feedURL != nil` channel resolves to `.podcast` with `.sequentialNewestFirst`; every `.spokenWord` progress-bar channel has `showsScrubbableProgress == true`.

**Verification gate:** Unit suite green (Phase 0 baseline + new MediaKind tests). No call sites changed, so behavior is provably identical.

**Acceptance:**
- `MediaKind`, `PlaybackBehavior`, `Channel.mediaKind`, `Channel.behavior`, `Track.mediaKind(in:)` exist and are fully tested.
- Favorites logic now derives from `MediaKind`; favorites tests still pass unchanged.

---

### PHASE 2 — Route behavior decisions through the new model (behavior-preserving refactor)

**Scope:** Replace scattered `category ==` / `contentType ==` / `feedURL !=` **behavioral** checks with `channel.behavior.X` / `channel.mediaKind`. One file at a time, each behind a green gate. Styling/`ia_queries`/stamp reads of `category` stay as-is.

**Order (lowest-risk first):**

**2.1 — `PlayerView.swift` (player surface, shallow).**
Replace `if channel.contentType == .spokenWord { progressBar }` with `if channel.behavior.showsScrubbableProgress { progressBar }`. (Sets up Phase 4.) Verify the same channels show the bar via the Phase 0 oracle.

**2.2 — `QueueManager.swift` (selection logic, 6 branches).**
Introduce a single resolver that maps a channel to an _effective_ queue style, preserving the radio-shuffle rule:
```swift
func effectiveQueueStyle(_ channel: Channel, shuffleMode: Bool) -> PlaybackBehavior.QueueStyle {
    if channel.feedURL != nil { return .sequentialNewestFirst }       // podcast invariant
    if channel.iaQueryEntry != nil { return .shuffledPool }           // radio invariant (preserve!)
    if channel.category == "Lectures" { return .shuffledPool }        // preserve usesShuffle()
    return channel.behavior.queueStyle
}
```
Then rewrite `_next` / `usesShuffle` to consult `effectiveQueueStyle`. **The manifest-only enforcement for the Curated category, the 30-day podcast dedup, and the isolation-stamp matching must be untouched.** Run the QueueManager tests; they must pass without modification. If any fails, your mapping diverged from current behavior — fix the mapping, not the test.

**2.3 — `PlayerViewModel.swift` (37 branches) — behavioral subset only.**
Replace behavioral conditionals (when to persist resume position, when book-skip is allowed, when to show chapters, when speed control applies, sleep-timer applicability) with `behavior.persistsResumePosition`, `behavior.supportsBookSkip`, `behavior.supportsChapters`, `behavior.supportsSpeedControl`, `behavior.supportsSleepTimer`. Do **not** restructure methods yet (that's Phase 3) — only swap the predicate. Leave stall/curation/stamp logic alone.

**2.4 — Remaining views** (`ChannelInfoView`, `ChannelListView`, `MainMenuView`, `iPodView`, `ChannelSelectorView`, etc.): swap **behavioral** branches to `behavior`/`mediaKind`. Leave `ChannelCategoryStyle` calls (color/gradient/icon by `category`) exactly as they are — that's presentation keyed on category, intentionally.

**Verification gate (after each sub-step):** Unit suite + Phase 0 baseline green. The baseline test is the proof that the refactor preserved behavior — it must never go red in this phase.

**Acceptance:**
- Grep for behavioral `category ==` / `contentType ==` / `feedURL !=` outside `MediaKind+Resolve.swift`, `ChannelCategoryStyle.swift`, `QueueManager.effectiveQueueStyle`, and the IA/stamp internals returns effectively nothing.
- All existing tests pass unmodified.

---

### PHASE 3 — Decompose the `PlayerViewModel` God object

**Scope:** Extract cohesive responsibility groups into focused `@MainActor` controllers in `Core/Services/Playback/`. `PlayerViewModel` becomes a **facade** that owns the published transport state and delegates everything else. No UI behavior changes.

**Extraction order (each is one commit, each behind a gate):**

1. **`SleepTimerController`** — owns `sleepTimerEndsAt`, `sleepAtEndOfTrack`, `startSleepTimer`, `setSleepAtEndOfTrack`, `cancelSleepTimer`. `PlayerViewModel` exposes the published fields by forwarding. Lowest coupling → do first.
2. **`BookmarkController`** — `bookmarksForCurrentTrack`, add/delete/seek bookmark, `fetchCurrentItemChapters`. Depends on DB + current track.
3. **`RecentlyPlayedController`** — recently-played + history reads/writes.
4. **`SessionRestoreController`** — `persistSession`, `restoreLastSession`, `migratedChannelId`.
5. **`RecommendationsController`** — `fetchRecommendations` (For-You channels).
6. **`AuditionController`** — `auditionTrack`, `stopAudition`, `stopAuditionWithoutRestore`, `failedAuditionTrackId`. **Preserve the "set failedAuditionTrackId before clearing currentTrack" invariant (§2.2) exactly.**
7. **`WholeItemController`** — `resolveItemParts`, `addEntireItemToPlaylist`, `playEntireCurrentItem`, `playAlbumTracks`, `playSequentialItem`, `probeCurrentTrack`, `partsAreClean`.

**Rules for each extraction:**
- The controller is constructed in `AppDependencies` (or by `PlayerViewModel` from injected deps) and held by `PlayerViewModel`.
- `@Published` properties that the UI binds to **stay on `PlayerViewModel`** (so no view needs to change its `@EnvironmentObject`), but their mutation logic moves into the controller; `PlayerViewModel` forwards. Alternatively, expose the controller as a nested `@Published` `ObservableObject` only if you also update the binding sites — prefer forwarding to minimize view churn in this phase.
- Move the corresponding tests to target the controller directly where possible (`SleepTimerTests`, `BookmarkTests`, `AutosaveBookmarkTests`, `RecentlyPlayedTests`, `IntentsTests`, `PlayerViewModelTests`). Tests should require minimal edits — mostly construction.
- Do **not** extract transport/queue/stall (`load`, `playTrack`, `advanceToNext`, `handleStallIfNeeded`, `handleLoadFailure`, `skip/seek/back`). Those remain the core of `PlayerViewModel`.

**Target end state:** `PlayerViewModel` drops from ~2,337 lines to roughly the transport+queue+stall core (~900–1,100 lines) plus thin forwarding. Each controller is independently unit-testable without spinning up the whole player.

**Verification gate (after each extraction):** Full unit suite green. `PlayerViewModelTests` and the moved suites pass. Manual smoke per §7.

**Acceptance:**
- `PlayerViewModel` no longer directly implements sleep-timer / bookmark / recently-played / session / recommendations / audition / whole-item logic.
- Each new controller has focused tests.
- All §2.2 invariants intact (grep for `failedAuditionTrackId`, `playbackContextToken`, the `seconds > 0` guard, and confirm they're preserved).

---

### PHASE 4 — Now Playing, rebuilt and behavior-composed (UI overhaul, part 1)

**Scope:** Build the **one** full-screen `NowPlayingSheet` and the **one** shared `MiniPlayer`, with the Now Playing controls **composed entirely from `behavior`**. This is the new player spine the whole app will share. Aggressive: the new Now Playing replaces `PlayerView` as the player surface; the two duplicate mini-players (currently copy-pasted inside `MainMenuView` and `HomeView`) collapse into one component.

**Steps:**
1. Create `Views/Player/` with a small composable control set, each a self-contained SwiftUI view bound to `PlayerViewModel`:
   - `TransportControls` (play/pause/skip — always present).
   - `ScrubBar` (rendered iff `behavior.showsScrubbableProgress`; draggable, with `.monospacedDigit()` time labels).
   - `SpeedControl` (iff `behavior.supportsSpeedControl`).
   - `SleepTimerControl` (iff `behavior.supportsSleepTimer`).
   - `ChapterButton` → presents `ChapterListView` (iff `behavior.supportsChapters`).
   - `ShuffleToggle` (iff `behavior.allowsShuffleToggle`).
   - `BookSkipControls` (next/prev book, iff `behavior.supportsBookSkip`).
   - `BookmarkButton` (iff `behavior.supportsBookmarks`).
2. Create `Views/Player/NowPlayingSheet.swift`: a full-screen sheet — large artwork, title/creator, `LicenseDisplay`/`SourceDisplay` badges, then `TransportControls` plus a stack that adds each accessory control behind a single `if channel.behavior.X`. **No `category`/`contentType` strings anywhere in this view.** It is presented as a sheet (swipe-down to dismiss) and uses standard navigation/dismiss affordances. The favorite (heart) control lives here too, using the existing `FavoritesStore`.
3. Create `Views/Player/MiniPlayer.swift`: one component (consolidating the two existing copies) — artwork, title, play/pause, tap-to-expand into `NowPlayingSheet`. Honors Reduce Transparency with an opaque fallback. Delete the inline mini-player code from `MainMenuView` and `HomeView` and route both to this component (they remain temporarily until Phase 5 removes their hosts).
4. Repoint Kids Mode's `NowPlayingScreen` to present the same `NowPlayingSheet`/controls so there is exactly one Now-Playing implementation app-wide.
5. Result per type, with **no per-type view code**:
   - **Music**: play/pause/skip + shuffle toggle. No scrub bar (radio), no speed/sleep/chapters.
   - **Audiobook**: scrub + speed + sleep + chapters + book-skip + bookmark + resume.
   - **Podcast / Lecture**: scrub + speed + sleep + bookmark + resume (no chapters, no book-skip).
   - **Ambient**: play/pause + sleep only.
6. The old `PlayerView.swift` is now dead; mark it for deletion in Phase 5 when its last referencing host is removed (additive-before-subtractive: don't delete it until nothing presents it).

**Verification gate:** Build green; extend `SmokeTests`/`PodcastUITests` to assert the correct control set appears per `MediaKind` (one representative channel each). Verify Dynamic Type (largest accessibility size), Dark Mode, Reduce Transparency, and VoiceOver labels on `NowPlayingSheet` + `MiniPlayer`. Manual smoke per §7.

**Acceptance:**
- One `NowPlayingSheet` and one `MiniPlayer` exist; the duplicated mini-players are gone.
- Control presence is driven 100% by `behavior`; zero type strings in the player views.
- Kids Mode and main app share the same Now-Playing implementation.

---

### PHASE 5 — Navigation overhaul: one `TabView`, parallel surfaces retired (UI overhaul, part 2)

**Scope:** This is the aggressive structural change. Replace the three co-equal entry points (`HomeView` grid, `MainMenuView` drill-down, `iPodView` click-wheel-as-root) with the **single `RootTabView`** from §4.3: Listen · Library · Search, the shared `MiniPlayer` docked above the tab bar, and Settings as a toolbar item. Product-visible and intended — the new structure ships as the default and only UI.

**Steps:**

1. **Build `RootTabView`** (`Views/RootTabView.swift`): a `TabView` with three tabs, each its own `NavigationStack`. Render the shared `MiniPlayer` once as a `safeAreaInset`/overlay above the tab bar, visible across all tabs whenever `currentTrack != nil`. SF Symbol per tab; inline or large titles per HIG.

2. **Listen tab** (`Views/Listen/ListenView.swift`): the curated/browse home. Migrate the *worthwhile* content out of the 1,700-line `HomeView` — For You row, the per-`MediaKind` browse sections, Live Music on This Day, Recently Added Audiobooks, curated discovery — as **small, separately-filed sections** under `Views/Listen/` (`ListenSection_ForYou`, `ListenSection_Music`, `ListenSection_Books`, `ListenSection_Podcasts`, `ListenSection_Lectures`, `ListenSection_Ambient`, `LiveMusicOnThisDaySection`, `RecentlyAddedAudiobooksSection`). Drop redundant/decorative grid chrome aggressively — KISS. A Settings gear lives in this tab's toolbar.

3. **Library tab** (`Views/Library/LibraryView.swift`): the user's own content in one obvious place — Playlists, **Favorites** (move `FavoritesScreen` here), **Recently Played** (move `RecentlyPlayedScreen` here), Downloads. Standard `List`/`NavigationStack`. This is where the previously scattered "my stuff" consolidates.

4. **Search tab** (`Views/Search/SearchTabView.swift`): full-screen `.searchable` over `SearchViewModel`, results → `NowPlayingSheet`. Reuse the existing search logic; just give it a first-class tab instead of being buried in the menu.

5. **One sectioning source**: add `Core/Models/LibrarySectioning.swift` defining the ordered `MediaKind` groups with label + SF Symbol, consumed by Listen (and Search facets). Delete the duplicated `categoryOrder` arrays in the old `HomeView` and `MainMenuView`.

6. **Re-root the app**: `ParsoRadioApp` now shows `RootTabView` (or `KidsHomeView` in Kids Mode) — nothing else. Then **delete the retired surfaces**: `HomeView.swift`, `MainMenuView.swift`, and `PlayerView.swift` (dead since Phase 4), plus any now-unreferenced sub-views. Update Intents/Siri entry points and `SplashView` transitions to land on `RootTabView`.

7. **Demote the click wheel**: remove `iPodView` as a navigation root. Either (a) keep it as an optional **"Retro" Now Playing skin** toggled from Settings (a single presentation choice over the same `PlayerViewModel`, not a navigation system), or (b) delete `iPodView.swift` entirely if the owner confirms. Default this plan to (a) unless told otherwise. Either way, `RootTabView` never depends on it.

8. **Keep `ClickWheelUITests` meaningful**: if (a), retarget them at the retro skin; if (b), delete them with the view.

**Verification gate:** Clean build green; `CuratedDiscoveryUITests`, `CurationUITests`, `PodcastUITests`, `SmokeTests` pass (retarget selectors to the new tab structure as needed — update the tests, never weaken assertions). Full manual smoke per §7, including Kids Mode, Siri launch, and offline. Verify Dynamic Type / Dark Mode / Reduce Transparency / VoiceOver on Listen, Library, Search, and the tab bar + mini-player.

**Acceptance:**
- `RootTabView` is the single navigation root; `HomeView.swift`, `MainMenuView.swift`, and `PlayerView.swift` are **deleted**.
- No second way to navigate; no `UserDefaults`-gated alternate of the new design.
- Favorites + Recently Played live under Library; Search is a first-class tab.
- Section order/labels/icons come from one `LibrarySectioning` source.
- The click wheel is no longer a root (retro skin in Settings, or removed).
- No file under `Views/Listen/` exceeds ~300 lines.

---

### PHASE 6 — Modular package boundaries (the escape hatch)

**Scope:** Turn the now-clean folder seams into **enforced** local Swift package boundaries, so a future standalone app is a drop-the-other-Features operation. Physical separation last, after logic is already separated.

**Steps:**
1. Create a local SPM package `ParsoCore` containing: `Core/Models/**`, `Core/Services/**` (API, Playback, Storage, Metadata, Download, Curation, Favorites), `Utilities/**` shared helpers. Mark public API `public`. Add it to `project.yml` `packages:` and depend the app target on it.
2. Move type-specific UI into three packages, each depending **only** on `ParsoCore`:
   - `MusicFeature` ← music Now-Playing control composition (shuffle/queue), music Listen sections.
   - `SpokenFeature` ← audiobook/podcast/lecture Now-Playing controls (chapters, speed, sleep, resume, book-skip, bookmarks), `ChapterListView`, podcast add/subscribe UI, their Listen sections.
   - `AmbientFeature` ← ambient/loop surface, `LoopingVideoView`, `ProceduralVisualizerView` if ambient-only.
   The shared `NowPlayingSheet`/`MiniPlayer` shell lives in the app (or a thin `PlayerUI` module in `ParsoCore`); the **accessory controls** it composes come from the Features via the `behavior` flags.
3. The app shell (`ParsoMusic` target) keeps: `ParsoRadioApp`, `AppDependencies`, `RootTabView`, the Listen/Library/Search tab containers, `MiniPlayer`/`NowPlayingSheet` shell, `KidsHomeView`, splash/terms/age-gate, Intents bridge, and the optional retro `iPodView` skin (if retained). It imports `ParsoCore` + all three Features and composes them.
4. **Enforce the no-cross-Feature rule**: no Feature package may import another. Add a CI check (a simple grep in `.github/workflows/ios.yml`) that fails if `import MusicFeature` appears in `SpokenFeature`, etc.
5. Update `project.yml` and regenerate. Update `AGENTS.md`/`README.md` source-tree sections to the new layout.

**Verification gate:** Full clean build from regenerated project; **all** test targets green; integration tests green; a TestFlight-style archive build succeeds locally or in CI.

**Acceptance:**
- `ParsoCore` + three Feature packages exist; app target composes them; no Feature→Feature imports (CI-enforced).
- All tests pass; CI ships as before.

---

## 6. The escape hatch: how to spin out a standalone app later (reference, not a task)

Document this in `AGENTS.md` after Phase 6 so future-you (or an agent) can act on data:

> To ship a standalone "Lorewave Books" app: create a new app target that depends on `ParsoCore` + `SpokenFeature` only; provide a shell with a books-only Home that filters `Channel.defaults` to `mediaKind ∈ {.audiobook}` (plus lectures/podcasts if desired); reuse the same `AppDependencies` wiring minus the unused Features. No core logic moves. Because Features never cross-import and all behavior flows through `MediaKind`/`behavior`, the audiobook experience is already fully formed inside `SpokenFeature`. Estimated effort: days, not a rewrite.

Only do this when analytics justify it (e.g. a large majority of sessions touch a single `MediaKind`). Until then, the unified app with type-aware internals is the product.

---

## 7. Manual smoke checklist (run after Phases 3–6)

For each of the five `MediaKind`s, pick one representative channel and verify:

- **Music** (`guitar-classical` or `piano-hour`): plays, shuffle toggle present and works, no scrub bar, skip works, no speed/sleep/chapters.
- **Audiobook** (`lv-general-fiction` or `great-books`): plays, scrub bar present, speed control works, sleep timer works, chapter list present, next/prev-book works, resumes at saved position on reopen, bookmark add/seek works, favoriting promotes to the book with a resume point.
- **Podcast** (`news-nprup-first`): newest episode plays from 0:00, sequential, scrub + speed + sleep present, no chapter list, resumes position.
- **Lecture** (`oxford-philosophy`): random radio-style selection, scrub + speed + sleep present, resumes.
- **Ambient** (`ambient-rain` loop, `ambient-yellowstone`): loops seamlessly, only play/pause + sleep timer, no scrub/speed/shuffle.

Plus: curator audition still flags failed tracks; Kids Mode entry/exit + allowed-channel gating intact; Siri "play channel" intent still launches; offline/downloaded playback unaffected; Recently Played + Playlists (mixed-type) intact.

**Navigation & HIG (after Phases 4–5):**
- Exactly one navigation root (`RootTabView`); no leftover way to reach the deleted `HomeView`/`MainMenuView`.
- Mini-player is docked above the tab bar on all three tabs whenever audio is loaded; tapping it expands `NowPlayingSheet`; swipe-down returns to the mini-player.
- Listen, Library (Playlists/Favorites/Recently Played/Downloads), and Search each work and deep-link into `NowPlayingSheet`.
- Settings reachable from the Listen toolbar.
- Dynamic Type at the largest accessibility size doesn't clip or overlap on any tab or on `NowPlayingSheet`; Dark Mode correct; Reduce Transparency shows opaque fallbacks; VoiceOver reads tab items, mini-player, and all behavior-composed controls with correct labels.
- If the retro click-wheel skin is retained, it's reachable only from Settings and drives the same `PlayerViewModel`; it is not a navigation root.

---

## 8. Phase → test/file quick map

| Phase | Primary files touched | Tests that must stay green |
|---|---|---|
| 0 | _(new)_ `Core/Tests/MediaKindBaselineTests.swift` | full unit suite |
| 1 | `Core/Models/MediaKind.swift`, `MediaKind+Resolve.swift`, `Favorite.swift` | `FavoritesTests`, new `MediaKindTests`, baseline |
| 2 | `PlayerView.swift`, `QueueManager.swift`, `PlayerViewModel.swift`, channel views | `QueueManagerTests`, `PlayerViewModelTests`, baseline, all |
| 3 | `Core/Services/Playback/*Controller.swift` (new), `PlayerViewModel.swift` | `SleepTimerTests`, `BookmarkTests`, `AutosaveBookmarkTests`, `RecentlyPlayedTests`, `PlayerViewModelTests`, `IntentsTests`, `AuditionTests` |
| 4 | `Views/Player/*` (new: `NowPlayingSheet`, `MiniPlayer`, control set); `KidsHomeView` repoint | `SmokeTests`, `PodcastUITests`, `ClickWheelUITests` |
| 5 | `Views/RootTabView.swift` (new), `Views/Listen/*`, `Views/Library/*`, `Views/Search/*` (new); `Core/Models/LibrarySectioning.swift` (new); **delete** `HomeView.swift`, `MainMenuView.swift`, `PlayerView.swift`; `ParsoRadioApp.swift` re-root; demote `iPodView.swift` | `CuratedDiscoveryUITests`, `CurationUITests`, `PodcastUITests`, `SmokeTests` (selectors retargeted to tabs) |
| 6 | `project.yml`, new SPM packages, `.github/workflows/ios.yml`, `AGENTS.md`/`README.md` | ALL targets incl. integration + archive |

---

## 9. Definition of done

- App still ships as one product; no separately-released app targets were created.
- `MediaKind` + `PlaybackBehavior` is the single source of truth for type behavior; behavioral `category`/`contentType`/`feedURL` checks are gone from views and the queue layer (presentation styling on `category` intentionally remains).
- `PlayerViewModel` is a transport/queue/stall facade delegating to focused, tested controllers; it is materially smaller.
- There is **one** navigation root (`RootTabView`: Listen · Library · Search) and **one** Now-Playing implementation (`NowPlayingSheet` + shared `MiniPlayer`); `HomeView.swift`, `MainMenuView.swift`, and `PlayerView.swift` are deleted, and the click wheel is no longer a navigation root.
- The Now-Playing surface composes its controls entirely from `behavior`; each `MediaKind` shows exactly its intended set; no type strings in player views.
- Section order/labels/icons come from one `LibrarySectioning` source; Favorites + Recently Played consolidated under Library; Search is a first-class tab.
- The new design ships on by default — it is **not** behind a feature flag.
- HIG/accessibility bar met on every new surface: Dynamic Type, Dark Mode, Reduce Transparency, VoiceOver.
- `ParsoCore` + three non-cross-importing Feature packages exist; CI enforces the boundary; a standalone-app spin-out is documented as a days-long task.
- Every gate passed; full unit + integration suites green; curation/kids/siri/offline invariants intact.
