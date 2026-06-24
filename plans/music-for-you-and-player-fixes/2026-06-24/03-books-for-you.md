# Books For You shelf + remove Curated Book / Live Music

Date: 2026-06-24 (follow-up to 00..02 in this folder)
Status: PLAN — awaiting review, not yet implemented.

> Repo state note: the prior batch (Music For You + player fixes, commit
> `310ee26`, merged `fdea530`) is committed and merged to `main` **locally but
> not yet pushed** — the local pre-push hook kept flaking on the unrelated,
> shared-singleton `PodcastSubscriptionStoreTests` on the iOS 26.5 sim
> (passes 755/755 clean on both 18.1 and 26.5). This Books-For-You work will be
> folded into the same push so CI runs once on the combined `main`.

## Goal (from request)

> "Made For You did a good job with audiobooks, so replace the Curated Book for
> You as 'Books for You' with the same methodology and format as Music for You,
> eliminate the curated book and live music on this day."

1. **Add "Books for You"** — an audiobook/spoken shelf that uses the *same store
   pattern and visual format* as "Music For You" (horizontal card scroller,
   plain section header, always-mounted, spinner while loading), placed directly
   below "Music For You".
2. **Eliminate "A Book Curated For You"** (the single curated-book row) from Home.
3. **Eliminate "Live Music on This Day"** from Home.

## Current behavior (grounded)

- Home order in `ListenView.body`: HomeTop (Jump back in), `MadeForYouSection`
  (Music For You), `BookForYouSection` (A Book Curated For You), `ExploreTypeRow`,
  `FeaturedTodaySection`, `LiveMusicSection`, Browse.
- "Music For You" = `MadeForYouSection` → `MadeForYouShelfStore.loadIfNeeded()`
  → daily cache → personalized `RecommendationsController.fetchMixedRecommendations(musicOnly: true)`
  → cold-start music IA collections (`etree/musopen/78rpm`). Renders horizontal
  `JumpBackInCard`s; tap → `playerVM.playRecentTrack(track)`.
- Daily cache table `made_for_you_daily_cache` is keyed `(day, position)` only —
  **no shelf discriminator**.
- "A Book Curated For You" = `BookForYouSection` → `BookForYouStore`/`BookForYouService`
  (single daily pick). "Live Music" = `LiveMusicSection` → `LiveMusicOnThisDayStore`/Service.
- Gate scope: pre-push hook + remote CI run **`ParsoMusicTests` (unit) +
  `ParsoMusicIntegrationTests`** only — **not** `ParsoMusicUITests`.
  `BookForYouIntegrationTests` and `LiveMusicOnThisDayIntegrationTests` test the
  *services* (kept), so they stay green. `LiveMusicOnThisDayUITests` (UI, not
  gating) asserts the Home section and would become invalid.

## Design

### 1. "Books for You" shelf (mirror Music For You)

- **New view** `BooksForYouSection` (plural, to avoid clashing with the existing
  singular `BookForYouSection`), a near-copy of `MadeForYouSection`:
  header `Text("Books for You")`, spinner on idle/loading, horizontal
  `JumpBackInCard` scroller, Retry on empty/failed.
- **Generalize the store** instead of duplicating: add a
  `MadeForYouShelfStore.Shelf` enum `{ .music, .books }` and an `init(..., shelf:
  .music)` param (defaulted to `.music` so the existing call site and
  `MadeForYouShelfStoreTests` compile unchanged). The store branches on `shelf`:
  - personalized recs: music → `fetchMixedRecommendations(musicOnly: true)`;
    books → `fetchMixedRecommendations(booksOnly: true)` (new flag, spoken-only,
    symmetric to `musicOnly`).
  - cold-start collections: music → `etree OR musopen OR 78rpm`;
    books → `librivoxaudio`.
  - **cache namespacing without a migration**: the store computes the cache
    day-key as `shelf == .books ? "books:\(day)" : day`. Music keeps the plain
    `day` key (backward compatible); books gets its own namespace. No schema
    change → additive-safe per AGENTS.md.
  - defensive filter: music drops `source == podcast/oxford_lectures` (already);
    books drops `source == podcast` (keep librivox audiobooks).
- **`RecommendationsController.fetchMixedRecommendations(musicOnly:booksOnly:)`**:
  add `booksOnly` (default false). When `booksOnly`, use only the `spoken`
  profile/queries (empty music profile) — exact mirror of the existing
  `musicOnly` branch.

### 2 & 3. Remove Curated Book + Live Music from Home

- `ListenView`: delete the `BookForYouSection(...)` and `LiveMusicSection(...)`
  calls and their `private struct` definitions; remove `selectedLiveEntry`
  state, the `.sheet(item: $selectedLiveEntry)` and the `LiveMusicDetailView`
  wiring. Insert `BooksForYouSection()` directly under `MadeForYouSection()`.
- **Keep** `BookForYou*` and `LiveMusic*` services/stores/models and their
  unit/integration tests (avoids dangling refs — e.g. `PlayerViewModel` uses
  `BookForYouService.workKey`, `LibrivoxBundledBooks` uses `BookForYouService.choose`
  — and keeps the integration gate green).
- Delete `ParsoRadio/UITests/LiveMusicOnThisDayUITests.swift` (the feature it
  drives is gone; UI tests are non-gating but shouldn't reference removed UI).

### New Home order

HomeTop → **Music For You → Books for You** → Explore → Featured today → Browse.

## Data-model deltas

- None to the DB schema. The shelf cache is namespaced via a string key prefix
  (`books:<day>`), so no column add / migration.

## Implementation steps

1. `RecommendationsController`: add `booksOnly` param (spoken-only branch).
2. `MadeForYouShelfStore`: add `Shelf` enum + `shelf` init param; branch recs /
   cold-start / cache-key / filter on it.
3. New `BooksForYouSection.swift` (mirror of `MadeForYouSection`). `xcodegen generate`.
4. `ListenView`: insert `BooksForYouSection`; remove `BookForYouSection` +
   `LiveMusicSection` (structs + state + sheet).
5. Delete `LiveMusicOnThisDayUITests.swift`. `xcodegen generate`.
6. Tests: add `BooksForYouShelfStoreTests` (mirror) + a `RegressionContractSourceTests`
   guard that `ListenView.swift` no longer references `LiveMusicSection`/`BookForYouSection`
   and does reference `BooksForYouSection`.
7. AGENTS.md: drop the "Live Music on This Day" contract; update "Music For You"
   contract ("A Book Curated For You" line → "Books for You renders directly
   below Music For You", audiobook-only).

## Testing strategy

- `xcodegen generate` then `ParsoMusicTests` gate (iPhone 16 / OS 18.1).
- New `BooksForYouShelfStoreTests`: cache namespace isolation (music vs books
  caches don't collide), cold-start source, idle→loaded state machine.
- Existing `MadeForYouShelfStoreTests` / `RecommendationsControllerTests` stay
  green (defaulted params).
- Integration gate unaffected (services retained).

## Open questions → see `decisions.md`

## FINALIZED MAP (post-review, full deletion)

**Delete (14 files):**
- LiveMusic: `Views/Listen/LiveMusicDetailView.swift`,
  `Core/Services/API/LiveMusicOnThisDayStore.swift`,
  `Core/Services/API/LiveMusicOnThisDayService.swift`,
  `Core/Services/API/LiveMusicCandidateValidator.swift`,
  `Core/Models/LiveMusicEntry.swift`, `Core/Tests/LiveMusicOnThisDayTests.swift`,
  `Integration/Tests/LiveMusicOnThisDayIntegrationTests.swift`,
  `UITests/LiveMusicOnThisDayUITests.swift`.
- BookForYou: `Core/Services/API/BookForYouService.swift`,
  `Core/Services/API/BookForYouStore.swift`, `Core/Models/BookForYouEntry.swift`,
  `Core/Services/API/LibrivoxBundledBooks.swift`,
  `Core/Tests/BookForYouServiceTests.swift`,
  `Integration/Tests/BookForYouIntegrationTests.swift`.

**Create:**
- `Utilities/WorkKey.swift` — relocated `workKey(author:title:)` + `cleanTitle`.
- `Views/Listen/BooksForYouSection.swift` — audiobook shelf (tap → play whole book).
- `Core/Tests/WorkKeyTests.swift`, `Core/Tests/BooksForYouShelfStoreTests.swift`.

**Edit:**
- `ListenView.swift`: drop LiveMusic/BookForYou sections (usages+structs+state+sheet);
  insert `BooksForYouSection()` under `MadeForYouSection()`.
- `PlayerViewModel.swift:1745`: `BookForYouService.workKey` → `WorkKey.normalized`.
- `DatabaseService.swift`: remove `book_curated_history` table/columns/schema/index +
  methods `fetchBookCuratedWorkKeys`, `fetchBookCuratedForDay`, `insertBookCurated`,
  `deleteBookCuratedForDay`, `fetchLeastRecentlyCurated`, `rowToBookForYouEntry`.
  KEEP `book_listened` + `recordBookListened`/`fetchBookListenedWorkKeys`.
- `RecommendationsController.swift`: add `booksOnly` (spoken-only).
- `MadeForYouShelfStore.swift`: add `Shelf {.music,.books}` param; per-shelf recs,
  cold-start (`librivoxaudio`), filter, and namespaced cache key (`books:<day>`).
- `RegressionContractSourceTests.swift`: remove `testLiveMusicServiceDoesNotFallbackToPoolFirst`;
  add guards (ListenView no longer references LiveMusicSection/BookForYouSection; does
  reference BooksForYouSection).
- `AGENTS.md`: remove "Live Music on This Day" contract; update Music/Books For You.

**Keep (not BookForYou/LiveMusic service tests):** `PlaybackContextTests` and the
`PlaybackContext.Origin.bookForYou/.liveMusic` enum cases (no production code sets
them; harmless; removal would cause needless churn).

**Unused-but-harmless leftover:** `Resources/.../bundled_books.json` (was only read by
the deleted `LibrivoxBundledBooks`). Left in place to avoid resource-wiring churn.

