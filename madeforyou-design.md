# RECOMMENDATIONS-DESIGN.md — "Made for You" v2

> The code already says `See RECOMMENDATIONS-DESIGN.md` in
> `RecommendationQueryBuilder.swift`, but the file never existed. This is it.
>
> Status: design / handoff. Pure-policy parts (`RecommendationQueryBuilder`)
> stay deterministic and unit-testable, matching the existing test suite.

---

## 1. Goal

A **Made for You** shelf that is:

1. **History-only & on-device.** Built solely from *this* user's plays + favorites.
   No other users, no profile upload, no accounts. The only network traffic is
   anonymous Internet Archive Solr queries built from the user's own taste tokens
   — the same kind of query the app already issues when you open any channel.
2. **Never a retread.** Never surfaces a track that is in history, in favorites,
   or was surfaced in a recent Made-for-You shelf.
3. **"Pleasant surprises."** Returns things *like* what you love but that you
   haven't discovered yet — adjacent artists / readers / genres, not just
   "more rows from the two collections you already open."
4. **Always fresh.** The shelf meaningfully changes between visits.
5. **A scrollable rail of tracks.** Surfaced as a horizontal section like "Jump
   back in" (≥10 picks), not a single tap-to-play channel card (§6.8).
6. **Works on day one without backfill.** Forward-only profile; a first-run
   onboarding seeds taste from the real catalog so new users get a full shelf
   immediately (§6.7).

## 2. Non-goals

- **No audio-embedding similarity in the app.** The CLAP/USearch work lives in
  `parso-ia-music-indexer` and would require querying a server — that breaks the
  on-device privacy story. This design is metadata/co-occurrence based. Embedding
  similarity is a *future* upgrade gated on the indexer exposing a private NN
  endpoint; explicitly out of scope here.
- No collaborative filtering (needs other users' data — violates goal 1).

---

## 3. Why v1 shows nothing / never surprises (root causes)

These are the things v2 fixes. All are grounded in the current code.

**A — History is coupled to the volatile `tracks` table (primary "shows nothing").**
`fetchRecentlyPlayedWithChannel` inner-joins `track_play_history → tracks` and
`continue`s past any play whose track row is gone. But `pruneChannelTracks`
(runs on **every** channel load) deletes that channel's tracks that aren't in the
*current* fresh query result, and `evictOldTracks` deletes more above 5000 tracks.
A played track survives only if it still happens to sit in its channel's current
top-N. So the *effective* (hydratable) history silently erodes toward "whatever is
cached right now," often dropping below `minPlays = 5` → recommender returns `nil`
→ empty state / "listen to 5 first." Same root cause makes "Jump back in" and the
Made-for-You **card visibility** (gated on `recentlyPlayedTracks(limit:1)`) flaky.

**B — Profile keyed on channel category, not track metadata.** A play counts only
if its channel's *current* category is exactly `"Curated Music"` or `"Audiobooks"`.
Plays via Search, playlists, Favorites, a since-removed collection, or **the
`for-you` channel itself** (recorded under `channelId == "for-you"`, category
`"For You"`) are invisible. So listening *through* Made for You never reinforces it.

**C — 30-day-only history.** `evictOldTracks` hard-deletes plays older than 30 days.
An intermittent listener can sit permanently under the 5-play gate.

**D — Pool = only your own channels (the reason there's no "surprise").** v1 counts
plays per channel, then re-runs *those exact collections'* IA queries and subtracts
what you played. By construction it can only return "more from the buckets you
already open, minus what you've heard." It never reaches an adjacent artist or a
neighboring genre.

**E — `downloads desc` popularity bias.** Every query is sorted by download count,
and you've usually already played the top items — so the *un-played remainder*
skews toward the less-loved tail. The opposite of a delightful pick.

**F — Favorites not excluded; no cross-session freshness.** v1 filters only history
ids, and nothing records what was previously surfaced, so the shelf repeats.

---

## 4. Architecture overview

```
   plays + favorites (metadata)        onboarding chips (first run, §6.7)
                  │  (incremental, on write)       │  (seed terms, no backfill)
                  ▼                                 ▼
        ┌─────────────────────────────────────────────┐   durable, survives
        │              TasteProfileStore               │── eviction & 30-day window
        └─────────────────────────────────────────────┘   (terms / seen / surfaced)
                  │ profile(bucket)            (decayed token weights per axis)
                  ▼
   RecommendationQueryBuilder (PURE) ── candidate IA queries, 3 novelty classes
                  │ queries + class tags
                  ▼
        InternetArchiveService.fetchTracks(iaQuery:matchTags:)   (reuse as-is)
                  │ raw candidates
                  ▼
   RecommendationsController ── exclude · score · MMR · MIN_SHELF top-up · log
                  │ ≥10 final tracks
                  ▼
        MadeForYouSection (horizontal rail, §6.8) ── tap → play + enqueue rest
```

The key structural move: **a durable `TasteProfileStore` decoupled from the
`tracks`/`track_play_history` tables.** That single change kills root causes A, B,
and C at once, because the profile no longer depends on volatile rows or on the
channel-category string.

---

## 5. Data model (new SQLite tables)

All on-device, in the existing `DatabaseService` DB.

```sql
-- Exponentially-decayed running term weights. Recency-aware, O(1) update.
CREATE TABLE taste_profile_terms (
  bucket TEXT NOT NULL,           -- "music" | "spoken"   (from MediaKind)
  axis   TEXT NOT NULL,           -- "creator" | "subject" | "composer"
  term   TEXT NOT NULL,           -- normalized token
  weight REAL NOT NULL,           -- decayed running sum
  last_ts REAL NOT NULL,          -- last update time (for decay-at-read/update)
  PRIMARY KEY (bucket, axis, term)
);

-- Durable exclusion set. Survives track eviction & the 30-day history window.
CREATE TABLE taste_seen_identifiers (
  identifier TEXT PRIMARY KEY,    -- IA item id  OR  work-key  (see §6.4)
  reason TEXT NOT NULL,           -- "played" | "favorited"
  ts REAL NOT NULL
);

-- FIFO ring of recently-surfaced recommendations → cross-session freshness.
CREATE TABLE reco_surfaced (
  identifier TEXT PRIMARY KEY,
  ts REAL NOT NULL
);
```

**Why running-decayed weights:** storing a raw count loses recency; recomputing
from history is impossible once tracks are evicted. Instead accumulate an
exponentially-weighted sum so each update is O(1) and read needs no rescan:

```
on observe(term, increment, now):
    decay = exp(-(now - last_ts) / TAU)      // TAU ≈ 21 days
    weight = weight * decay + increment
    last_ts = now
```

`increment` per observation = `favoriteBoost × playCountBoost`:
- base play = 1.0
- favorited item = ×3.0 (`FAVORITE_BOOST`)
- repeated plays already collapse in `track_play_history` PK, so optionally fold
  play count via `1 + log(1 + plays)` if you keep a count column; otherwise 1.0.

---

## 6. Algorithm

### 6.0 Bucketing

Bucket by **`Track.mediaKind`**, not channel category:
`music`/`ambient → "music"`, `audiobook/lecture → "spoken"`, `podcast` excluded
(news/podcasts aren't "discover more like this" material). This is what makes
plays from *any* context count — the fix for root cause B.

### 6.1 Profile maintenance (write path, incremental)

Hook two existing call sites so the profile updates as a side effect — no batch
job, no dependence on the tracks table later:

- In `DatabaseService.recordPlayed(channelId:trackId:)` *and* on favorite-add,
  resolve the track's metadata **once, now** (you have the full `Track` in hand at
  both call sites) and:
  - upsert `taste_profile_terms` for each `creator`, each `subject` (= lowercased
    `tags`), and `composer`, in the track's bucket, via the decay update above;
  - upsert `taste_seen_identifiers(identifier, reason)` — store both the IA id and
    the work-key (§6.4).

Because this captures metadata **at play/favorite time**, later eviction of the
track row is irrelevant. Root causes A and C disappear.

> Subject damp (cheap IDF substitute): when reading the profile, divide a term's
> weight by `1 + log(1 + distinctSeedsCarryingTerm)` so ubiquitous tags
> (`"music"`, `"audio"`) don't dominate. Keep a per-term seed counter, or maintain
> a small stop-list (`["music","audio","spoken word","librivox", …]`).

### 6.2 Candidate generation — `RecommendationQueryBuilder` (PURE)

Input: `profile(bucket)` (top-N terms per axis, post-damp) + a date seed.
Output: a list of `(iaQuery, anchorTerm, noveltyClass, requestedCount)`.

Three novelty classes, mixed by a tunable allocation (default 55 / 35 / 10):

- **EXPLOIT** (reliable): same creator/composer you already love.
  `creator:"<top creator>"` / `subject-as-composer` queries. Surfaces *other*
  works by artists/readers you play, that you haven't heard.
- **EXPLORE** (the surprise axis): subject **co-occurrence** expansion. Take a top
  subject you love; pair it with a subject that co-occurs with it in your seeds but
  is **not** in your top-played set: `subject:"<loved>" AND subject:"<adjacent>"`.
  Or `subject:"<loved>" -creator:"<already-heard creator>"`. Same neighborhood,
  street you haven't walked.
- **SERENDIPITY** (small, further reach): a top subject crossed with a sibling
  subject drawn by a **date-seeded** RNG from the broader candidate universe.

**Candidate universe = wider than your channels, but quality-respecting:**

- **music:** search the **entire curated-collection universe**
  (`collection:(c1 OR c2 OR … )` over *all* of `IACollectionStore`'s collections /
  tiers), **not** restricted to the channels you already play. This directly
  answers the warning in `InternetArchiveService` about 78rpm/amateur leakage:
  you reach *other curated collections you haven't tried* (= surprises) while
  keeping the quality decision those collections encode. SERENDIPITY may step
  outside to `mediatype:audio` but only with a hard download/quality floor.
- **spoken:** all of LibriVox (`collection:(librivoxaudio)`) by author/subject,
  not just your subscribed reader/genre channels.

Allocate counts across anchors by their profile weight (reuse the existing
`allocateSamples` idea with a `minPerAnchor` floor), then split each anchor's
slots across the three classes by the mix above. Keep the function pure: same
profile + same seed ⇒ same query list ⇒ unit-testable.

### 6.3 Fetch

Reuse `InternetArchiveService.fetchTracks(iaQuery:matchTags:)` **unchanged**.
Pass `matchTags: ["for-you"]` (or the sub-channel id) so candidates carry the
registry stamp playback isolation expects. Run the per-query fetches concurrently
with the existing `withTimeout` + `TaskGroup` pattern already in
`RecommendationsController`.

### 6.4 Exclusion (hard) — the "never a retread" guarantee

`excludeKeys = seen_identifiers(played ∪ favorited) ∪ reco_surfaced(recent)`

Exclude a candidate if **any** of its keys is in `excludeKeys`:
- its IA `id`,
- its **work-key** = `parentIdentifier ?? normalize(creator + "·" + title)`
  (so the *same audiobook re-uploaded*, or a multi-part item, collapses to one and
  can't sneak back in under a different id),
- its `parentIdentifier`.

This is read straight from `taste_seen_identifiers`, so it's complete regardless of
whether the original tracks were evicted. Fixes root cause F's first half + goal 2.

### 6.5 Scoring & diversity

For each surviving candidate `c`:

```
affinity(c)   = Σ_token∈c  profileWeight[token]            // creators+subjects+composer
              / ( sqrt(profileNorm) * sqrt(|c.tokens|) )   // cosine-flavored

novelty(c)    = fraction of c.tokens that are in the profile's ADJACENCY set
                (co-occurring with loved terms) but NOT in the TOP-PLAYED set
                → rewards "new but related", not "exact retread"

popPrior(c)   = normalized log(1 + downloads)              // qualityScore
                → kept LOW weight; just enough to avoid broken/amateur uploads,
                  deliberately NOT the dominant signal (fixes root cause E)

score(c) = W_AFFINITY*affinity + W_NOVELTY*novelty + W_POP*popPrior
           // defaults: 0.55 / 0.35 / 0.10
```

Then **greedy MMR re-rank for diversity** so the shelf isn't 12 tracks by one
artist:

```
picked = []
while |picked| < K and candidates not empty:
    best = argmax_c [ score(c) - LAMBDA * maxSim(c, picked) ]
    // sim = Jaccard over {creator} ∪ {subjects}
    picked.append(best); remove best
```

`LAMBDA ≈ 0.5`. Take top **K = 20–30**.

### 6.6 Determinism & freshness

- Seed the RNG used in SERENDIPITY + any shuffles with a **date seed**
  (`yyyy-MM-dd`), matching the date-seeded deterministic-pick approach used
  elsewhere in the app. → "Today's Made for You" is stable within a day.
- After picking the final set, **append their work-keys to `reco_surfaced`**
  (FIFO, cap `RECO_SURFACED_CAP ≈ 500`). → tomorrow's shelf is genuinely new.
  This is the second half of goal 2 + all of goal 4.

### 6.7 Cold-start — onboarding-seeded (no backfill)

**Decision: forward-only, no backfill.** On first launch after the upgrade the
existing `track_play_history` is *not* re-scanned to construct a profile. The
profile starts empty and accumulates from the next play/favorite onward (§6.1).
This keeps the migration trivial and avoids inheriting any of the v1 history-loss
artifacts. The day-one gap that forward-only creates is filled by **onboarding**.

**Onboarding seeds the profile from the real catalog.** A first-run screen asks
"what do you like to hear?" with multi-select chips. Each chip is backed by a real
`collection:` id (from `default_collections.json`) or a real subject/creator seed,
so the picks it produces are things the app can actually deliver — no aspirational
genre that returns nothing. Selecting a chip writes weighted terms into
`taste_profile_terms` (bucket `"music"`), exactly as if the user had played a
couple of tracks from that area; the §6.2 generator then runs unchanged.

| Chip (user-facing) | Profile seed (real catalog) |
|---|---|
| Piano | `collection:tedjonespiano` + `subject:piano` |
| Bach & Baroque | `subject:classical` + `creator:(Bach OR Handel OR Vivaldi)` |
| Jazz | `collection:(sfjazz OR cujazz OR davidwnivenjazz)` |
| Spanish Guitar | `collection:aadamjacobs` + `subject:guitar` |
| Classical | `collection:russian_classical_collection` + `subject:classical` |
| World & Folk | `collection:(musica-campesina OR music-of-the-world-istanbul OR voa-music-time-in-africa)` |
| Reggae & Dub | `collection:crucialriddm_music` |
| Classic LPs | `collection:(vinyl_bostonpubliclibrary OR vinyl_robert-haber-records)` |
| Live Radio | `collection:imcradio` |
| Opera | `collection:vinyl_frank-defreytas-memoria-opera` |

Seeding rules:
- For a `collection:`-backed chip, fetch one cheap page of that collection and seed
  the **creator** and **subject** terms that actually occur in it (so the profile
  is populated with real tokens the candidate generator can expand on), rather than
  storing the raw `collection:` clause. For a pure creator/subject chip, seed those
  tokens directly.
- **Seed weight < a real play.** Seed at `ONBOARDING_SEED_WEIGHT` ≈ 1.5–2× one
  play's increment. Enough for a good day-one shelf, but with `TAU = 21d` decay the
  user's actual listening overtakes the onboarding priors within ~6–8 weeks. This
  is deliberate: onboarding is a *prior*, not a permanent pin.
- Chips are editable later (Settings → "What you like"); re-running just re-seeds.
- The catalog is the source of truth — when collections are added/removed, the chip
  list is regenerated from `default_collections.json` so it never drifts.

**Degradation ladder (no usable profile at generation time):**
- Skipped onboarding **and** no plays/favorites yet → hide the rail; show the
  existing Welcome card. (No fake/empty shelf.)
- Profile thin but non-empty → still produce EXPLOIT results. Gate on
  "profile has ≥1 usable creator/subject," **not** on a hard `minPlays` count
  (removes root cause C's interaction with the 5-play threshold).
- `spoken` bucket can reuse the same pattern with a small set of LibriVox genre
  chips later; out of scope for this pass (onboarding is music-only, matching the
  brief).

### 6.8 Surfacing — horizontal rail (UI)

Made for You becomes its **own horizontal section**, identical in treatment to
"Jump back in" (`HomeTopSection`), not the single tap-to-play `FeaturedCard` it is
today in "Featured today."

- **Cards are individual tracks** (artwork + title + artist, 118–120pt), reusing
  the `JumpBackInCard` layout. A small gradient-`sparkles` glyph marks the section
  header; subtitle: "Fresh picks from your taste · refreshes daily."
- **Minimum 10.** The controller must return **≥ `MIN_SHELF` (10)** so the rail
  visibly scrolls. If EXPLOIT+EXPLORE come up short after exclusion, top up from
  SERENDIPITY (and, last resort, relax the work-level dedup) before giving up.
- **Tap a card = play that track**, then enqueue the remaining rail picks as the
  up-next queue — so it still behaves like a station once entered, while staying
  browsable. (Records play under a `for-you` context; since the profile is now
  metadata-keyed per §6.1, that self-play still counts correctly — fixing v1's
  self-cannibalization.)
- Place the rail high on the Listen screen (above "Jump back in"). The existing
  "Featured today" Made-for-You card is removed to avoid two entry points.
- Visibility gate: shown whenever the profile is non-empty (onboarding done **or**
  any play/favorite exists). Decoupled from the flaky `recentlyPlayedTracks(limit:1)`
  check that currently gates the card.

---

## 7. Tuning constants (one place)

| Constant | Default | Meaning |
|---|---|---|
| `TAU` | 21 days | recency half-life-ish for term decay |
| `FAVORITE_BOOST` | 3.0 | favorite vs plain play weight |
| `CLASS_MIX` | 55/35/10 | EXPLOIT / EXPLORE / SERENDIPITY |
| `W_AFFINITY/W_NOVELTY/W_POP` | 0.55/0.35/0.10 | score weights |
| `LAMBDA` | 0.5 | MMR diversity strength |
| `K` | 24 | shelf size (target) |
| `MIN_SHELF` | 10 | hard floor; rail must return at least this many |
| `ONBOARDING_SEED_WEIGHT` | ~1.5–2× a play | day-one seed strength per chip; decays out |
| `RECO_SURFACED_CAP` | 500 | freshness ring size |
| `DOWNLOAD_FLOOR` (serendipity) | e.g. ≥ 200 | quality floor when leaving curated set |

---

## 8. Privacy properties (explicit)

- 100% on-device. The three new tables never leave the device; no sync, no upload.
- Network = anonymous IA Solr GETs built from the user's own creator/subject
  tokens. This is the **same** surface the app already exposes when you open any
  channel (a channel *is* an IA query). No new third party, no identifier sent.
- One inherent caveat to document honestly: an IA query string encodes taste
  (`creator:"X"`), so a network observer of archive.org traffic could infer
  interests — but that is already true of normal browsing and is unavoidable for
  any IA-backed recommender. No regression vs today.

---

## 9. Integration points (real files)

| File | Change |
|---|---|
| `DatabaseService.swift` | + 3 tables (§5); + `TasteProfileStore` methods (upsert term, upsert seen id, fetch profile, fetch exclusion set, push/read surfaced ring); hook `recordPlayed` to also update profile + seen ids. |
| *(new)* `TasteProfileStore.swift` | Thin actor over the 3 tables; the decay-update math; profile read with subject damp. |
| `RecommendationQueryBuilder.swift` | Replace channel-weight logic with profile→candidate-query generation (§6.2). **Keep pure & deterministic.** Update `RecommendationQueryBuilderTests`. |
| `RecommendationsController.swift` | Rework `fetchMixedRecommendations` to: read profile, get queries, fetch, exclude (§6.4), score+MMR (§6.5), enforce `MIN_SHELF` top-up (§6.8), log surfaced (§6.6). Reuse existing `withTimeout`/`TaskGroup`. |
| Favorite-add path (`FavoritesStore` / `FavoriteButton`) | Call the profile/seen-id update on add. |
| *(new)* `MadeForYouSection.swift` (in `Views/Listen/`) | Horizontal rail mirroring `HomeTopSection`; track cards (`JumpBackInCard`); tap → play track + enqueue rest (§6.8). Placed above "Jump back in" in the Listen list. |
| `HomeSections.swift` | Remove the Made-for-You `FeaturedCard` from `FeaturedTodaySection` (single entry point). |
| *(new)* `OnboardingTasteView.swift` + first-run flag | Multi-select chip screen (§6.7); on continue, seed `taste_profile_terms`. Re-openable from Settings. |
| `PlayerViewModel.load(channel:)` "For You" branch | Orchestration mostly intact; the `for-you` channel still exists for "play my whole shelf as a station," now sourced from the same generator. Empty-state copy fires only on a truly empty profile. |
| `Channel.swift` | No change to the For You channel defs. |

Note: `fetchMixedRecommendations` already has no `minPlays` gate — good, keep that;
just make sure the empty-state copy fires only on a truly empty profile (§6.7).

---

## 10. Rollout — two scopes

### MVP (fixes "shows nothing" + adds real surprise + the rail, smallest diff)
1. Add the 3 tables + `TasteProfileStore`; hook `recordPlayed` + favorite-add.
   **Forward-only — no history backfill.**
2. Switch the profile to metadata+bucket (kills B), durable (kills A, C).
3. **Onboarding chip screen** (§6.7) so first-run users get a non-empty profile
   without backfill.
4. **Horizontal Made-for-You rail** (§6.8): new section, track cards, `MIN_SHELF`=10,
   tap → play + enqueue rest. Remove the old `FeaturedCard` entry point.
5. Candidate gen: EXPLOIT + EXPLORE over the **wider curated/LibriVox universe**
   (kills D). Skip SERENDIPITY + full MMR for v1; a simple per-anchor cap is fine,
   but keep the `MIN_SHELF` top-up so a thin profile still fills the rail.
6. Exclusion = played ∪ favorited ∪ surfaced ring (kills F, goals 2 & 4).
7. Drop `sort=downloads desc` reliance: fetch a wider page, rank by
   `affinity + low popPrior` (kills E).

### Full (this doc)
Add SERENDIPITY class, novelty bonus, MMR diversity, subject-damp IDF, date-seeded
daily stability, the `spoken`-bucket onboarding chips, and per-card "more/less like
this" feedback into the profile.

---

## 11. Test plan

Pure/unit (no network), matching the existing `ParsoMusicTests` style:

- **QueryBuilder:** given a synthetic profile → asserts query set has the right
  class mix, never emits a query whose only term is in TOP-PLAYED for EXPLORE,
  honors `minPerAnchor`, and is deterministic under a fixed date seed.
- **Exclusion:** played/favorited/surfaced ids and work-keys are all filtered;
  same-work re-upload under a new id is still excluded.
- **Scoring/MMR:** higher-affinity ranks above lower; MMR prevents >N from one
  creator in top-K; popPrior can't outrank a clearly-on-taste item.
- **Decay store:** running-sum update matches closed-form for a known sequence;
  recency ordering is correct; eviction of the source track does **not** change
  the profile or the exclusion set (regression guard for root cause A).
- **Cold start / onboarding:** chip selection seeds the expected terms at
  `ONBOARDING_SEED_WEIGHT`; a seeded-but-no-plays profile yields a full ≥`MIN_SHELF`
  rail; skipped onboarding + no plays → rail hidden (no empty shelf), no crash.
- **MIN_SHELF top-up:** a deliberately thin profile still returns ≥10 after the
  SERENDIPITY/dedup-relax top-up path.

Integration (network, `ParsoMusicIntegrationTests`): one end-to-end that seeds a
small history, runs the controller against live IA, and asserts the result is
non-empty, disjoint from history+favorites, and disjoint from a prior run's
surfaced ring.
