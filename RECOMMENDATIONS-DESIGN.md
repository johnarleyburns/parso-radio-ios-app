# Parso Music — Competitive Analysis & "For You" Recommendation Redesign

_Written 2026-05-24. **Status: Part 2 implemented & shipped to `main`
(`6374c1e`)** — two-arm recommendations + `downloads:[100]`, curl-validated,
tests rewritten. The related **infinite-buffering fix** (stall-storm give-up cap
+ blue repeat badge) shipped first (`a8b7c52`, CI green). **CarPlay** (a Part 1
gap) is scaffolded on the `carplay-support` branch — gated on Apple's entitlement
grant; see `CARPLAY.md`._

---

# Part 1 — Competitive position: Parso vs the field

## What Parso is

An iPod-click-wheel internet radio for **public-domain / Creative Commons**
audio: classical, LibriVox audiobooks, Oxford lectures, FMA genres, public-radio
news (RSS), ambient loops, and kids — **77 channels**. Free, no account, no ads,
no tracking; **source + license shown for every track**; in-app DMCA reporting.
Universal (iPhone + iPad).

## Feature parity matrix (Parso state verified in code)

| Capability | Parso | Apple Music | Spotify | Audible | Overcast | Pocket Casts |
|---|---|---|---|---|---|---|
| Cost / account | **Free, none** | Paid + acct | Free+ads / Paid | Paid | Free / Paid | Free / Paid |
| Catalog | PD/CC (IA + FMA) | Licensed | Licensed | Licensed | Your podcasts | Your podcasts |
| Variable speed 0.5–2× | ✅ | ✅ (pods) | ✅ (pods) | ✅ | ✅ | ✅ |
| Sleep timer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Bookmarks | ✅ | — | — | ✅ | ✅ (clips) | ✅ |
| Chapter / part list | ✅ | ✅ | — | ✅ | ✅ | ✅ |
| Exact-position resume | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Offline downloads | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Lock-screen ±15 s (spoken) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| AirPlay / Share | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Per-track license transparency | ✅✅ **unique** | — | — | — | — | — |
| In-app DMCA / takedown | ✅ **rare** | — | — | — | — | — |
| **CarPlay browsing** | ❌ (Now-Playing only) | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Siri / App Intents** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Widgets / Live Activity** | ❌ | ✅ | ✅ | — | ✅ | ✅ |
| **Apple Watch app** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Queue / Up Next** | ❌ | ✅ | ✅ | — | ✅ | ✅ |
| **Discovery / recommendations** | ⚠️ naive | ✅✅ | ✅✅✅ | ✅ | — | — |
| Smart Speed / silence trim | ❌ | — | — | — | ✅✅ | ✅ |
| Downloads-management UI | ❌ (delete-all) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Cross-device sync | ❌ (no acct) | ✅ | ✅ | ✅ | ✅ | ✅ |

## Where Parso wins (the moat)

1. **Genuinely free, no account, no ads, no tracking** — almost nobody else.
2. **Licensing transparency + DMCA path** — unique, and a real trust/Review moat
   for a UGC-sourced catalog.
3. **Breadth in one app** — music + audiobooks + lectures + news + ambient + kids.
4. **Distinct identity** — the click-wheel is memorable; nobody else ships it.
5. **Privacy posture** — "Data Not Collected" is true, not marketing.

## Where Parso is behind (ranked by listener ROI)

1. **Discovery quality** — the "For You" engine is naive (Part 2). Spotify's
   Discover Weekly is the bar; Parso can't match catalog-scale ML, but it can
   nail "more of the artists/genres you love" using data it already has.
2. **CarPlay browsing** — the biggest missing *surface* for an eyes-free, long-
   form audio app. Needs Apple's CarPlay-audio entitlement (request lead time).
3. **Siri / App Intents, widgets, Live Activity** — modern table stakes.
4. **Apple Watch** — low priority (system Now-Playing already gives wrist
   transport for free; a native app is a separate target for marginal gain).
5. **Smart Speed / silence trimming** — Overcast's signature; great for lectures
   and audiobooks specifically.
6. **Downloads-management UI**, **queue/up-next**, **cross-device sync** (the
   last needs accounts → out of scope by design).

## Strategic read

Parso's edge is **free, honest, broad**. Its weakest link _relative to user
expectation_ is **discovery** — and it already has the inputs (listening
history) and the surface (the For You channels) to do it well **without accounts
or ML infrastructure**. So improving For You is the highest-leverage quality
investment that plays to existing strengths. That is Part 2. (CarPlay is the next
one after, but it's gated on an Apple entitlement, so it's a parallel track.)

---

# Part 2 — "For You" recommendation redesign

## Problem (verified by reading the code + live curl, 2026-05-24)

1. **Inert boosts.** `RecommendationQueryBuilder.musicQuery` OR-joins
   `creator:"X"^3` (signal) with `subject:"S"` (broad) into one query, and
   `InternetArchiveService.fetchTracks` fetches it with **`sort=random`**. Solr
   `^` boosts only change *relevance* ranking — which random sort discards. So a
   broad `subject:"Classical"` match is drawn **as often as** a real performer
   the user actually played. The `^3` does nothing.
2. **Amateur long tail.** `downloads:[20 TO *]` lets low-effort uploads in.
3. **Viral novelty.** Pushing the download floor too high *re-introduces* noise
   (e.g. "Baby Mozart" has huge download counts).
4. **"More of the same" only** — no structured discovery within taste.

Symptom for a Beethoven/Mozart listener: the pool surfaced "Baby Einstein," a
vaporwave act, amateur Jamendo piano, and a tabla recital.

## Data (live `archive.org/advancedsearch`, sample of 60 per level)

Representative history = Beethoven + Mozart creators, "Classical" subject.

| downloads floor | numFound | ~noise in sample |
|---|---|---|
| `[20 TO *]` (current) | 33,833 | ~23% |
| **`[100 TO *]`** | **28,074** | **~15%** |
| `[200 TO *]` | 22,672 | ~15% |
| `[500 TO *]` | 10,815 | ~18% |
| `[1000 TO *]` | 4,496 | ~30% ⚠️ |

Also measured: the pool is **~95% streamable** (38/40 resolve a valid MP3 in
~1 s; ~5% HTTP 500) — confirming the buffering symptom was the missing stall cap
(now shipped), **not** a dead pool. Query tuning is for **quality**, not
buffering.

## Design — two-arm fetch + composition bias

Replace the single OR'd, randomly-sorted query with **two separate arms** whose
**pool composition** is biased toward signal. (Composition, not play order:
`QueueManager` already random-picks from the saved pool, so if the pool is ~70%
artists-you-played, ~70% of plays will be too — no need to fight `sort=random`.)

- **Arm A — Signal (creators).** Creator-only query of the user's top played
  artists. Every result is an artist they chose. `downloads:[100]`, same NOT
  exclusions, `sort=random` for variety within the arm.
- **Arm B — Discovery (genres).** Subject-only query of the user's top
  genres/subjects. Brings in *new* artists, but bounded to the user's taste.
  `downloads:[100]`, same NOT exclusions, `sort=random`.
- **Mix.** Build the channel pool from ~**70% Arm A / 30% Arm B** (tunable
  constant), dedupe by id, drop already-played, stamp `matchTags=[channel.id]`.
- **Fallbacks.** No creators → Arm B only (current behavior, preserved). No
  subjects → Arm A only. Either arm empty → use the other.
- **Books** get the same split, inside the `librivoxaudio` /
  `audio_bookspoetry` collections (Books has no noise problem today, but the
  split keeps author-signal dominant and is symmetric/maintainable).

Why this fixes all four problems: the **70/30 composition guarantees creator
dominance** regardless of random sort (kills the inert-boost issue); discovery is
**bounded to the user's own subjects** (no cross-genre novelty); `downloads:[100]`
trims the amateur tail **without** inviting viral novelty.

## Implementation plan

**`RecommendationQueryBuilder.swift`**
- Split `musicQuery` → `musicCreatorQuery(fromHistory:)` + `musicSubjectQuery(fromHistory:)`.
  Same for books. Each pure/deterministic; returns `nil` when its dimension is
  empty. Drop the now-pointless `^3` boosts (they did nothing under random sort).
  Both carry `downloads:[100 TO *]` + the existing NOT exclusions.
- Add a pure mixer:
  `mixPool(creatorTracks:[Track], subjectTracks:[Track], total:Int = 120, creatorShare:Double = 0.7) -> [Track]`
  — take `round(total*creatorShare)` from A (or all if fewer), fill the rest from
  B, dedupe by id, preserve determinism.

**`PlayerViewModel.fetchRecommendations(for:)`**
- Build both arm queries; fetch in parallel (`async let`) via
  `archiveService.fetchTracks(iaQuery:matchTags:[channel.id])`.
- `mixPool(...)`, then drop `playedIds` (as today), return.
- Keep the `minPlays` gate and the "listen to N tracks first" prompt unchanged.

**No change** to stamping / `QueueManager` / the channel pool model
(`matchTags=[channel.id]` unchanged) — so the album-boost, recents, and prune
logic all keep working as-is.

## Tests

- `musicCreatorQuery` contains the creators, `downloads:[100`, the NOT clause, and
  **no** `subject:` arm; `musicSubjectQuery` is the mirror (subjects, no creators).
- Both `nil` under `minPlays`; creator query `nil` with no creators; subject query
  `nil` with no subjects.
- `mixPool`: honors the 70/30 ratio, dedupes overlap, is deterministic, and
  degrades gracefully when one arm is short (fills from the other).
- Update/replace `testMusicQueryFavorsTopCreatorsAndExcludesSpokenWord`.

## Validation (pre-push, per CLAUDE.md)

- **curl** the creator-only and subject-only arms for a representative history;
  confirm `numFound > 0` and eyeball clean samples (no Baby-Einstein/vaporwave).
- `swiftc -parse` every changed file.
- Run via CI (no local iOS toolchain). This bundle also carries the
  `downloads:[20 → 100]` change.

## Risks / open questions

- **70/30 ratio** is a first guess — exposed as a constant; revisit after
  dogfooding. (Could later make it adapt to how many distinct creators exist.)
- **Creator-name matching FMA→IA is fuzzy** — an FMA artist may not exist on IA,
  so Arm A can be thin for FMA-heavy listeners; Arm B fallback covers it.
- **Two queries** double fetch cost — run in parallel; acceptable.
- **Not in scope:** true collaborative filtering / cross-user signals (needs
  accounts), and a relevance-sorted "your artists' greatest hits" third arm
  (possible later enhancement).

## Out-of-scope follow-ups noted during the competitive pass (not this bundle)

CarPlay browsing (needs Apple entitlement — start the request early), Siri/App
Intents, Now-Playing widget + Live Activity, Overcast-style silence trimming, a
downloads-management screen, and a queue/Up-Next view. Tracked here so they
aren't lost; each is its own design.
