# Recommendation Bucketing Fix — Overview

Date: 2026-06-24
Topic: Music For You leaks audiobooks; Books for You ignores listening history.

## Symptoms (reported)

- GOOD: "Music For You" and "Books for You" both mount and render.
- BAD 1: "Music For You" contains non-music tracks (LibriVox audiobooks).
- BAD 2: "Books for You" ignores history — it shows generic popular LibriVox
  recommendations instead of tailoring to listening history like the old
  "Made for You".

## Root-cause summary

### Shared root cause — audiobook plays mis-bucketed into the *music* taste bucket
`TasteProfileStore.seedFromTrack` derives its bucket from
`track.mediaKind(in: channel)`. `Track.mediaKind(in:)`
(`Core/Models/MediaKind+Resolve.swift:19`) can only recognise an audiobook
*with a channel* — `source` is `"internet_archive"` for both music and LibriVox.
With `channel == nil` it always returns `.music`.

Two seeding paths pass `channel: nil`:
- The history **backfill** (`Core/Services/Playback/MadeForYouShelfStore.swift:169`)
  seeds every historical track with `channel: nil` → all past audiobook plays
  land in the **music** bucket; the **spoken** bucket stays empty.
- Direct/search/playlist live plays where `currentChannel == nil`
  (`ViewModels/PlayerViewModel.swift:1186`/`1191`).

Consequence: music bucket polluted with book creators/subjects (→ Music For You
recommends audiobooks); spoken bucket empty (→ Books for You always cold-starts
to generic LibriVox).

### Bug 1 (Music shows LibriVox) — additional causes
1. **Serendipity query is unscoped.** `RecommendationQueryBuilder.swift:86`
   emits `subject:"A" AND subject:"B" AND mediatype:audio AND downloads:[200 TO *]`
   — no collection filter, no spoken-word exclusion → freely returns audiobooks.
   (Exploit/explore/fallback are scoped to `allCollectionIDs`, which is the
   music-only `default_collections.json` set, so they are mostly safe.)
2. **Polluted music bucket** (shared cause) feeds book subjects/creators into all
   music queries.
3. **Weak defensive net.** `MadeForYouShelfStore.filtered()` for `.music` only
   drops `source == "podcast"`/`"oxford_lectures"`. IA audiobooks
   (`source == "internet_archive"`) pass through.

### Bug 2 (Books ignores history) — additional cause
4. **Books queries are scoped to music collections.**
   `RecommendationsController.fetchMixedRecommendations` builds spoken queries with
   `allCollectionIDs = extractCollections(IACollectionStore.shared.collections)`,
   which is the *music* collection set (`default_collections.json` has no LibriVox).
   So even with a populated spoken profile, book queries become
   `creator:"<author>" AND (collection:cujazz OR …)` → ~0 matches → cold-start.
   The builder never targets `librivoxaudio`.

## Design principles

- The SQLite database (tracks + `track_play_history`) is the source of truth.
  Reconstruct taste buckets from authoritative play history, not from a
  channel-less heuristic.
- A *channel* served from an Audiobooks/Lectures/Podcast surface is authoritative
  about content kind. Where no spoken channel is available, fall back to
  channel-free track signals (`source` + channel-isolation stamp tags).
- Query generation must be *shelf-aware*: music excludes LibriVox/spoken-word;
  books target `librivoxaudio`.
- Additive-only schema changes. No destructive migrations to user data tables
  beyond the taste-profile rebuild (which is itself reconstructable from history).

## Phased rollout

| Phase | Branch | Depends on | Scope |
|-------|--------|------------|-------|
| 1 | `fix/reco-classification-core` | main | `Track.inferredMediaKind`, channel-aware backfill, `seedFromTrack` bucketing | 
| 2 | `fix/reco-shelf-aware-queries` | Phase 1 | shelf-scoped query generation + controller threading |
| 3 | `fix/reco-filter-and-migration` | Phase 2 | defensive `filtered()` backstop, taste-profile migration v2, persist onboarding chip IDs |

One PR per phase, stacked. Verify each with `ParsoMusicTests` before push.

## Section index

- `01-media-kind-classification.md` — Phase 1
- `02-shelf-aware-queries.md` — Phase 2
- `03-defensive-filter-and-migration.md` — Phase 3
- `decisions.md` — settled decisions
