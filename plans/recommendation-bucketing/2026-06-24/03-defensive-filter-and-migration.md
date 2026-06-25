# Phase 3 — Defensive filter backstop + taste-profile migration v2

## Problem
- Even with scoped queries, a stray spoken track could slip into the Music shelf
  (no client-side backstop today).
- Existing users carry a polluted music bucket and an empty spoken bucket from the
  v1 backfill. They need a one-time repair that preserves onboarding emphasis.

## Current behavior
- `MadeForYouShelfStore.filtered()` `.music` only drops `podcast`/`oxford_lectures`;
  `.books` only drops `podcast`.
- `ensureTasteBackfillIfNeeded()` runs once (`currentBackfillVersion == 1`), seeds
  with `channel: nil`, and never re-buckets.
- Onboarding chip selections are not persisted.

## Design

### Defensive filter
```
private func filtered(_ tracks: [Track]) -> [Track] {
    switch shelf {
    case .music: return tracks.filter { $0.inferredMediaKind == .music }
    case .books: return tracks.filter { $0.inferredMediaKind == .audiobook }
    }
}
```
Recommendation tracks are stamped `pmreg::for-you`, so most won't carry `lv-*`;
the music shelf primarily relies on Phase 2 query scoping, with this filter as a
backstop for any `source=="podcast"/"oxford_lectures"` or `lv-*`-stamped strays.
For books, cold-start fetches `librivoxaudio` items (audiobook by source/parent),
but `inferredMediaKind` defaults `for-you`-stamped librivox items to `.music`,
so the books filter must NOT use `inferredMediaKind` alone — it keeps tracks that
are NOT clearly music-only-source (i.e. drop `podcast`/`oxford_lectures` and known
`pmreg::` *music* registry stamps, keep the rest). Concretely:
- `.books`: drop `source=="podcast"` and `source=="oxford_lectures"`; keep the rest.

(Music gets the strict `inferredMediaKind == .music` keep; books stays lenient
because librivox cold-start lacks an audiobook stamp.)

### Migration v2
Bump `currentBackfillVersion` → 2. New `migrateTasteProfileV2`:
1. Snapshot current **music** bucket terms (`term/axis → weight`).
2. `db.clearTasteProfileTerms()` (new additive DB method; deletes all rows in the
   `taste_profile_terms` table only).
3. Rebuild from `fetchRecentlyPlayedWithChannel` using channel-aware seeding
   (Phase 1) → correct music + spoken buckets from real listens.
4. Residual restore: fetch the rebuilt music bucket + spoken bucket. For each
   snapshot term, `residual = snapshotWeight - rebuiltMusicWeight`. Re-add
   `residual` to the music bucket **only if** the term has zero weight in the
   spoken bucket (i.e. not audiobook-origin) and `residual > 0.5`. This preserves
   onboarding (≈1.75) and favorite (≈3.0) emphasis while dropping migrated
   audiobook pollution.

Run order in `ensureTasteBackfillIfNeeded`:
- version 0 → fresh users: existing v1 behavior (seed from history channel-aware),
  set version 2.
- version 1 → existing users: run `migrateTasteProfileV2`, set version 2.
- version ≥ 2 → no-op.

### Persist onboarding chips
`OnboardingTasteView` writes `@AppStorage("onboardingChipIDs")` (comma-joined
selected ids) on completion, so future rebuilds can replay onboarding exactly.
(Not used by the v2 migration itself — recorded for forward use.)

## Data-model deltas
- New DB method `clearTasteProfileTerms()` (no schema change).
- New UserDefaults key `onboardingChipIDs`.
- `currentBackfillVersion` 1 → 2.

## Implementation steps
1. `DatabaseService.swift`: add `clearTasteProfileTerms()`.
2. `MadeForYouShelfStore.swift`: bump version; add `migrateTasteProfileV2`;
   strengthen `filtered()`.
3. `TasteProfileStore.swift`: add a direct-set helper if needed for residual
   restore (`setTermWeight` / reuse `upsertTerm`).
4. `OnboardingTasteView.swift`: persist `onboardingChipIDs`.

## Testing strategy
- `clearTasteProfileTerms` empties only taste terms.
- Migration: pre-seed music bucket with an audiobook-origin term + history of an
  audiobook play under an Audiobooks channel; after v2, term moves to spoken and
  is absent from music; an onboarding-only music term survives in music.
- `.music` filter drops an `lv-*`-stamped track; `.books` filter drops a
  `source=="oxford_lectures"` track and keeps a librivox cold-start track.

## Open questions
- Decay means residual arithmetic is approximate; the 0.5 floor separates
  onboarding/favorites from single decayed plays. Acceptable.
