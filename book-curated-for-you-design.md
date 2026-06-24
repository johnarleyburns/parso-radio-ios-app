# BOOK-CURATED-FOR-YOU-DESIGN.md — daily single-book pick

> Companion to RECOMMENDATIONS-DESIGN.md (Made for You). Same philosophy
> (on-device, history-only, never-repeat), but a **single audiobook per day** in a
> full-width card, built on the same daily-rotation pattern the app already uses
> for **Live Music on This Day** (`LiveMusicOnThisDayStore` / `…Service`).
>
> Status: design / handoff.

---

## 1. Goal

One **"A Book Curated For You"** card on the Listen screen that:

1. **Picks a single audiobook**, chosen from the user's **own audiobook history**
   (on-device, no other users). If they've heard no books yet, it picks a popular
   one at random — specifically one of the **top 100 General Fiction titles on
   LibriVox**, not just any book.
2. **Never recommends a book in the user's listening history.** We keep a durable
   record of every book the user has ever listened to and exclude it.
3. **Gives a new book every single day.** Today's pick is stable within the day and
   different tomorrow — driven by randomness **plus** a permanent ledger of every
   book ever surfaced here, so the same recommendation never comes back.
4. **Brings the user back daily.** The "new every day" guarantee is the hook.
5. **Matches the Live Music card form factor:** full screen width, same row height
   (72pt), 56×56 cover thumbnail — placed directly **above** "Live Music on This Day."

## 2. Non-goals

- Not a shelf — exactly one book. (Made for You §6.8 is the multi-item rail.)
- No onboarding chips for books in this pass (the top-100 fallback is the cold
  start). The `spoken`-bucket onboarding is a later option (Made for You §6.7).
- No audio-embedding similarity (same reasoning as the Made for You doc §2).

## 3. Relationship to Made for You (shared infra)

This feature reuses two things from RECOMMENDATIONS-DESIGN.md when present:

- The **`spoken`-bucket taste profile** (authors = creators, genres = subjects)
  built from audiobook plays + favorites — used to pick *on-taste* books.
- The **durable seen-identifiers** concept — "books ever listened to."

**It can also ship standalone.** If `TasteProfileStore` isn't built yet, this doc
specifies a minimal durable audiobook ledger (§5) that provides both signals on its
own. Build either way; if both exist, unify on `TasteProfileStore`.

The **daily-rotation mechanics** mirror `LiveMusicOnThisDayStore` exactly: a
MainActor `ObservableObject` `.shared` store with `entry`, `isLoading`,
`loadIfNeeded()`, `refresh()`, backed by a service that caches per day. The one
deliberate difference: Live Music only avoids its *immediately previous* pick
(`lastPickedID`); books must avoid **every** past pick, permanently (§5.4).

---

## 4. Data model (new, durable SQLite tables)

On-device, in the existing `DatabaseService` DB. Both survive track eviction and
the 30-day history window (the volatility that breaks v1 — see Made for You §3).

```sql
-- Every book the user has ever LISTENED to (work-level). Written on audiobook play.
CREATE TABLE book_listen_history (
  work_key   TEXT PRIMARY KEY,   -- normalized author·title  (see §5.0)
  identifier TEXT NOT NULL,      -- the IA item actually played
  title      TEXT,
  author     TEXT,
  subjects   TEXT,               -- comma-joined IA subjects (optional, aids §5.2)
  last_ts    REAL NOT NULL
);

-- Every book ever SURFACED as "Book Curated For You". Permanent never-repeat ledger
-- AND the per-day cache (look up WHERE day = today to get today's pick).
CREATE TABLE book_curated_history (
  work_key   TEXT PRIMARY KEY,
  identifier TEXT NOT NULL,
  day        TEXT NOT NULL,      -- "YYYY-MM-DD" it was shown
  title      TEXT,
  author     TEXT,
  ts         REAL NOT NULL
);
CREATE INDEX idx_book_curated_day ON book_curated_history(day);
```

> If `TasteProfileStore` exists: `book_listen_history` may be replaced by querying
> `taste_seen_identifiers` (spoken). Keep `book_curated_history` regardless — the
> permanent never-repeat ledger is unique to this feature.

---

## 5. Algorithm

### 5.0 What "a book" is (identity)

A LibriVox title can have multiple recordings (different readers / versions). Track
and exclude at the **work level**, not the item id, so hearing one recording of
*Frankenstein* prevents recommending another:

```
work_key = normalize(author + "·" + cleanTitle)
cleanTitle = title with "(version N)" / "(dramatic reading)" / reader suffixes stripped, lowercased
```

`identifier` is still stored for playback and the cover URL.

### 5.1 Daily rotation & caching (mirror LiveMusicOnThisDayStore)

`BookForYouStore` (`@MainActor`, `.shared`):

```
loadIfNeeded():
    today = "YYYY-MM-DD"
    if today == lastLoadedDay { return }          // already shown today
    if cached = book_curated_history.row(day: today) {
        entry = hydrate(cached); lastLoadedDay = today; return
    }
    entry = await generatePick(day: today)        // §5.2 / §5.3
    lastLoadedDay = today
```

- **Stable within the day:** once `book_curated_history` has a row for today, that
  exact book is returned all day (and after relaunch).
- **New the next day:** a new day has no cached row → `generatePick` runs, and
  because every prior pick is in the ledger, it can't reselect one (§5.4).
- `refresh()` (pull-to-refresh / debug): deletes today's row and re-generates,
  inserting the replaced pick still counts as "surfaced" so it won't return either.

Use a full **`YYYY-MM-DD`** key (not Live Music's `MM-DD`) — books rotate by
calendar day, not "on this day in history."

### 5.2 Personalized candidate pool (has audiobook history)

Same idea as Made for You §6.2, restricted to LibriVox and producing *candidates to
pick one from*:

- **Authors you've heard (EXPLOIT):** for the top authors in the `spoken` profile
  (or distinct authors in `book_listen_history`), query
  `collection:librivoxaudio AND creator:"<author>"` — surfaces *other* books by
  authors the user already finished.
- **Genres you like (EXPLORE):** for the user's top audiobook subjects, query
  `collection:librivoxaudio AND subject:"<genre>"` — books in the same genres they
  haven't heard. This is the "pleasant surprise" axis.
- Pull a modest page each (e.g. rows=40, `sort=downloads desc` so candidates are
  quality LibriVox recordings), union them into the candidate pool.

Reuse `RecommendationQueryBuilder` if it exists; otherwise these two query shapes
are all that's needed.

### 5.3 Cold-start fallback (no audiobook history)

Pool = **top 100 LibriVox General Fiction by downloads:**

```
collection:librivoxaudio AND subject:"General Fiction"
fl[]=identifier,creator,title,subject,downloads ; sort[]=downloads desc ; rows=100
```

(Matches the existing `lv-general-fiction` registry intent; use the focused
`subject:"General Fiction"` to honor "top 100 general fiction." Broaden to the
`lv-general-fiction` OR-set only if 100 isn't reached.)

Pick one at random from this pool (after exclusion §5.4, with the date seed §5.6).

### 5.4 Exclusion — never a listened book, never a repeat

Build the candidate list, then drop any candidate whose `work_key` (or `identifier`)
is in **either**:

- `book_listen_history` — books ever listened to, **or**
- `book_curated_history` — books ever surfaced here before.

This is read from durable tables, so it holds even after the source tracks are
evicted. (Goal 2 + Goal 3.)

### 5.5 Pick + widening ladder (never empty)

```
generatePick(day):
    pool   = candidatePool()                       // §5.2, else §5.3
    pool   = pool.excluding(listened ∪ everSurfaced)   // §5.4
    pick   = choose(pool, seed: day)               // §5.6
    if pick == nil: pool = widen()                 // see ladder
    persist(pick → book_curated_history, day)      // also the never-repeat ledger
    return pick
```

Widening ladder (only if exclusion empties the pool — i.e. heavy users who've
exhausted their niche):
1. personalized authors+genres →
2. top-100 General Fiction →
3. broader LibriVox fiction (`lv-general-fiction` OR-set, rows=300) →
4. any `collection:librivoxaudio` by downloads (rows=500).
If *everything* is exhausted (essentially never), surface the least-recently
recommended past pick rather than showing nothing.

### 5.6 Determinism + the never-repeat guarantee

- `choose(pool, seed: day)` uses a **date-seeded RNG** (seed = `YYYY-MM-DD`), so a
  relaunch on the same day before the row is cached still yields the same book.
  Optionally weight the draw lightly toward profile affinity (more like Made for
  You) — but uniform-random over the on-taste pool is fine and robust for one pick.
- The moment a book is chosen it's written to `book_curated_history`, so it is
  excluded from every future day. Randomness picks *which* new book; the ledger
  guarantees it's *new*. Together: a different book every day, never repeating, and
  never one already heard.

---

## 6. UI — full-width card above Live Music

A new `Section` in `ListenView`, **immediately above** the `LiveMusicSection`,
visually identical to it (so the two read as a matched pair):

- `Section { … } header: { Text("A Book Curated For You") }`
- Row is an `HStack(spacing: 0)`, **`.frame(height: 72)`**:
  - 56×56 cover (`RoundedRectangle(cornerRadius: 10)`), `AsyncImage` from
    `https://archive.org/services/img/<identifier>` with a default book cover on
    failure (add `book-curated-default` asset, mirroring `live-music-default`).
  - `VStack(alignment:.leading, spacing:3)`: title (`.subheadline.weight(.medium)`,
    2 lines), author (`.caption`, secondary, 1 line), reason line (`.caption2`,
    tertiary) — e.g. *"Because you enjoyed Mary Shelley"* (personalized) or
    *"Popular on LibriVox"* (cold start).
  - `Spacer`, then a `play.circle.fill` (`.title2`, `.blue`) → start the book.
- Row tap → open the LibriVox item in the existing `ItemDetailView`. Play button →
  begin playback of the book's first section.
- `.task { await BookForYouStore.shared.loadIfNeeded() }`,
  `.refreshable { await BookForYouStore.shared.refresh() }`.

States (mirror Live Music): loading (gray cover + `ProgressView`, "Finding your
book…"); empty (only if the widening ladder truly fails — "No book today, check
back tomorrow"); loaded (as above).

Placement note: with Made for You now a rail (companion doc §6.8), the Listen order
becomes: Made for You rail → Explore → Featured today → **A Book Curated For You** →
Live Music on This Day → Library.

---

## 7. Privacy

Identical posture to Made for You §8: 100% on-device; the two new tables never leave
the device; the only network calls are anonymous LibriVox/IA Solr queries built from
the user's own authors/genres — the same surface the app already uses for any
channel. No accounts, no other users' data, no upload.

---

## 8. Integration points (real files)

| File | Change |
|---|---|
| *(new)* `BookForYouStore.swift` (`Core/Services/API/`) | `@MainActor ObservableObject .shared`, mirrors `LiveMusicOnThisDayStore`: `entry`, `isLoading`, `loadIfNeeded()`, `refresh()`. |
| *(new)* `BookForYouService.swift` (`Core/Services/API/`) | Candidate pool (§5.2/§5.3), exclusion (§5.4), pick + widening (§5.5), date seed (§5.6). Models the LibriVox queries; reuse `InternetArchiveService` if convenient. |
| *(new)* `BookForYouEntry.swift` (`Core/Models/`) | `identifier`, `title`, `author`, `subjects`, `reason`; `coverURL = services/img/<identifier>`; `workKey`. Mirror `LiveMusicEntry`. |
| `DatabaseService.swift` | + 2 tables (§4); methods: record audiobook listen (work-level), fetch listened set, fetch/insert today's curated pick, fetch ever-surfaced set. |
| `recordPlayed` (write path) | When the played track is a LibriVox/audiobook (`MediaKind`), upsert `book_listen_history` at work-level — **durable**, independent of `track_play_history`. |
| `ListenView.swift` | Add `BookForYouSection` **above** `LiveMusicSection` (§6). |
| `ItemDetailView.swift` | Reused as the book detail target on row tap (no change, or thread the identifier through). |
| Assets | Add `book-curated-default` cover image (parallel to `live-music-default`). |

Reuses from Made for You (if built): `TasteProfileStore` spoken profile +
`taste_seen_identifiers` + `RecommendationQueryBuilder`.

---

## 9. Rollout — two scopes

### MVP (ship the daily book, standalone)
1. Tables + `book_listen_history` hook on audiobook play (durable "ever listened").
2. `BookForYouStore`/`Service` mirroring Live Music; `YYYY-MM-DD` daily cache.
3. Cold-start path only at first (top-100 General Fiction, random, excluded by both
   ledgers) — already satisfies "new daily, never repeat, never a heard book."
4. Personalization: seed authors/genres from `book_listen_history` (EXPLOIT+EXPLORE).
5. The full-width card above Live Music.

### Full
Use the `spoken` `TasteProfileStore` profile for affinity-weighted picks, add the
personalized "reason" line, the widening ladder, and (optional) a small `spoken`
onboarding so day-one personalization beats the generic top-100.

---

## 10. Test plan

Pure/unit (no network), matching `ParsoMusicTests`:

- **Daily stability:** two `loadIfNeeded()` calls same day → identical pick (cached);
  simulated next day → different pick.
- **Never-repeat:** after N simulated days, all N picks are distinct work-keys; a
  pick already in `book_curated_history` is never returned again.
- **Never-listened:** any work-key in `book_listen_history` is excluded; hearing
  *version 2* after recommending *version 1* is blocked by work-key normalization.
- **Cold start:** empty `book_listen_history` → pick comes from the top-100 General
  Fiction pool; deterministic under a fixed date seed.
- **Widening ladder:** an exhausted personalized pool falls through to General
  Fiction → broader LibriVox without returning nil.
- **Durable ledgers:** evicting the source track does **not** remove the
  listened/surfaced record (regression guard against the v1 volatility bug).

Integration (network): one end-to-end that runs three consecutive simulated days
against live LibriVox and asserts three distinct, never-before-seen books with valid
cover URLs.
