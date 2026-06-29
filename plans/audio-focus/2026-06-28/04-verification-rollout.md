# 04 — Schema Deltas, Migration Safety, Rollout & Verification

## Consolidated Schema Deltas (all additive)
| Delta | Type | Safety |
|---|---|---|
| Built-in podcast license registry (new bundled resource, e.g. `podcast_licenses.json`) | New static asset | No DB impact |
| `LicenseType.userSubscription` **or** `Track.isUserSubscription` (D-5) | Additive enum case / defaulted field | Old rows decode to existing default; no migration |
| Taste-profile backfill version bump v4→v5 (`MadeForYouShelfStore.swift:50–51`) | Versioned, idempotent | Clears stale *music* taste terms only; no row deletes |
| Remove `music-for-you` from `ia_queries.json` | Resource edit | Registry lookups for that id simply return nil |

**No destructive DB migration.** `tracks` and `track_play_history` keep all columns and rows. Legacy `media_kind = "music"` rows are read but excluded from user-facing shelves (`DatabaseService.fetchRecentlyPlayedWorks` + `MediaKind+Resolve` hidden path). `pruneChannelTracks()`/`evictOldTracks()` channel-filter invariants (AGENTS.md) unchanged.

## Phased Rollout (one branch + PR per phase; stack on unmerged deps)
| Phase | Branch | Depends on | Gate |
|---|---|---|---|
| P0 | `audio-focus/00-tag-and-plan` | — | docs only; tag exists |
| P1 | `audio-focus/01-recs-music-removal` | P0 | unit tests |
| P2 | `audio-focus/02-iacollections-fma-removal` | P0 | unit tests |
| P3 | `audio-focus/03-search-ui-language` | P1, P2 (stack) | unit + UI smoke |
| P4 | `audio-focus/04-player-media-model` | P1,P2,P3 (stack) | unit tests |
| P5 | `audio-focus/05-rights-podcast-licensing` | P0 | unit + integration |
| P6 | `audio-focus/06-copy-privacy-docs` | P1–P5 | source guards |
| P7 | `audio-focus/07-verification` | P1–P6 | full gate + UI |

Each phase: `xcodegen generate` (if files added/removed) → local `ParsoMusicTests` gate → commit (reference phase id) → PR. Pre-push hook runs unit tests. If simulator degrades: `killall -9 com.apple.CoreSimulator.CoreSimulatorService`.

## Test Plan
**Commands (AGENTS.md):**
```bash
xcodegen generate
xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ParsoMusicTests
```
Integration (slow, real APIs): LibriVox IA fetch, Oxford lecture fetch, podcast parsing, whole-book playback, search, recently played.

**New source-guard tests** (extend `RegressionContractSourceTests`) — fail if shipping (non-test, non-historical-plan) code contains: `Music For You`, `music-for-you`, `Free Music Archive`, `FMAService`, `Internet Archive Collections`, `10%`, `auto-renewable`.

**New behavior tests:**
- Search has no `.music`/`.albums` scope; default = audiobooks.
- Recommendations return LibriVox audiobooks only (no podcasts/lectures/music).
- Legacy `media_kind="music"` history rows are excluded from Jump Back In / shelves.
- No music player surface is selectable (`activeMediaKind` never `.music` for any seeded content).
- `PodcastRSSService`: built-in feed → registry license; user feed → neutral state.
- `PrivacyInfo.xcprivacy` contains FileTimestamp + DiskSpace categories.

**UI smoke** (`-uiTestSeed`, DEBUG `UITestSupport`): first launch, Listen, Search, Library, Now Playing, Books for You, podcast add, lecture playback render — no music surface.

> Reminders: XCTest runs alphabetically; run suites sequentially (shared singletons); `Track` init `partNumber` before `parentIdentifier`; `Channel` init `category` before `icon`, `preferredSource` before `feedURL`.

## Acceptance Criteria (mirrors handoff)
- [ ] `pre-audio-focus` tag exists at starting HEAD (`0ec3d07…`). **DONE (P0).**
- [ ] Plan docs exist under `plans/audio-focus/2026-06-28/` before code changes. **DONE (P0).**
- [ ] No music / albums / FMA / IA music collections / Music For You / music search / music player surface in user-facing behavior.
- [ ] Built-in podcasts verified with cited reusable licenses, or removed.
- [ ] Public + in-app privacy/terms copy match the app and cite LibriVox, Oxford, retained podcast licensing accurately.
- [ ] Tip jar remains; no donation/fundraising/proceeds-to-IA text.
- [ ] Privacy manifest covers current caching/storage API use.
- [ ] Build + unit gate pass after XcodeGen regeneration.

## Closeout (per AGENTS.md §3)
Re-read each phase plan vs implementation; reconcile divergences in docs; update `current_state.md`; update `README.md` for user-facing/architecture changes; then commit, merge to `main`, push.
