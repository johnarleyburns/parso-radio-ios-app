# Decision sheet — Books For You / removals

## Answers (recorded verbatim 2026-06-24)
- **D1 Scope**: *Fully delete services + tests* (BookForYou* and LiveMusic*).
- **D2 Tap**: *Play the whole book* — resolve all parts via
  `archiveService.fetchTracksForIdentifier` and `playerVM.playAlbumTracks`.
- **D3 Cold-start**: *librivoxaudio only*.
- **D4 Order**: *Jump Back In (when history exists) → Music For You →
  Books For You → Explore → Featured → Browse*; Live Music fully removed.
- **D5 Cache**: namespace daily-cache key per shelf (`books:<day>`), no migration.

## Consequence captured during audit (no further decision needed)
`BookForYouService.workKey` / `cleanTitle` are used by **core audiobook taste
tracking** (`PlayerViewModel.recordBookListenedIfAudiobook` → `db.recordBookListened`),
not just the curated-book UI. They are **relocated** to a new
`Utilities/WorkKey.swift` utility (behavior-preserving) so deletion of
`BookForYouService` does not regress audiobook taste/exclusion. The
`book_listened` table and `recordBookListened`/`fetchBookListenedWorkKeys` are
**kept**; only the curated-pick ledger `book_curated_history` and its methods are
removed.

---

## Original options (for reference)

## D1. Scope of "eliminate"
- **(Recommended) UI-only removal**: remove the Curated Book and Live Music
  *sections from the Home screen*, but keep their services/stores/models and
  unit+integration tests. Lowest risk; keeps the integration gate green; avoids
  dangling references (`PlayerViewModel.BookForYouService.workKey`,
  `LibrivoxBundledBooks.BookForYouService.choose`).
- **Full deletion**: also delete `BookForYou*` / `LiveMusic*` services, models,
  stores, and their tests. Larger surgery; must rewire `PlayerViewModel` and
  `LibrivoxBundledBooks`; deletes integration tests.

## D2. "Books for You" card tap behavior
- **(Recommended) Mirror Music For You** → `playerVM.playRecentTrack(track)`
  (plays the tapped audiobook track; identical methodology/format to Music For You).
- **Resolve full book** → fetch all parts (`archiveService.fetchTracksForIdentifier`)
  and `playAlbumTracks(...)`, like the old Curated Book did (starts the whole book).

## D3. Books cold-start collections
- **(Recommended) `librivoxaudio` only** (true public-domain audiobooks).
- Broaden (e.g. add other spoken collections) — name them if desired.

## D4. Home order / Live Music
- Confirm final order: Jump back in → **Music For You → Books for You** →
  Explore → Featured today → Browse, with **Live Music on This Day fully gone**.

## D5. Cache strategy
- **(Recommended) Namespace the daily-cache key per shelf** (`books:<day>` vs
  `<day>`), no DB migration.
- Add a `shelf` column to `made_for_you_daily_cache` (additive, defaulted) —
  only if you prefer an explicit column over a key prefix.
