# Book Curated For You — Implementation Plan

> Derived from `book-curated-for-you-design.md` + `book-curated-mockup.html`.
> Target: iOS 17.0+, SwiftUI + MVVM, SQLite-backed.

## Architecture

```
BookForYouStore (Singleton, @MainActor, ObservableObject)       [NEW]
    |   .shared entry, isLoading, loadIfNeeded(), refresh()
    |
    uses BookForYouService (struct)                             [NEW]
        |   generatePick(for day) -> BookForYouEntry?
        |   candidate pool, exclusion, widening ladder, date seed
        |
        +-- SQLite book_curated_history (day cache + never-repeat ledger)
        +-- SQLite book_listen_history (ever-heard exclusion)
        +-- TasteProfileStore (spoken bucket for personalization)
        +-- InternetArchiveService.fetchTracks(iaQuery:) for LibriVox queries

BookForYouSection (private View in ListenView.swift)            [MODIFY]
    |   mirrors LiveMusicSection form factor
    |   72pt row, 56x56 cover, title/author/reason, play button

DatabaseService                                                 [MODIFY]
    +-- book_listen_history table
    +-- book_curated_history table
    +-- 7 new query methods

PlayerViewModel.playTrack()                                      [MODIFY]
    +-- conditionally calls recordBookListened when audiobook
```

## Files

### New
| File | Location |
|---|---|
| `BookForYouEntry.swift` | `ParsoRadio/Core/Models/` |
| `BookForYouStore.swift` | `ParsoRadio/Core/Services/API/` |
| `BookForYouService.swift` | `ParsoRadio/Core/Services/API/` |
| `BookForYouTests.swift` | `ParsoRadio/Core/Tests/` |
| `BookForYouIntegrationTests.swift` | `ParsoRadio/Integration/Tests/` |

### Modified
| File | Change |
|---|---|
| `DatabaseService.swift` | +2 tables, +7 methods |
| `PlayerViewModel.swift` | +book listen hook in playTrack |
| `ListenView.swift` | +BookForYouSection above LiveMusicSection |

## Database Schema

```sql
CREATE TABLE IF NOT EXISTS book_listen_history (
    work_key   TEXT PRIMARY KEY,
    identifier TEXT NOT NULL,
    title      TEXT,
    author     TEXT,
    subjects   TEXT,
    last_ts    REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS book_curated_history (
    work_key   TEXT PRIMARY KEY,
    identifier TEXT NOT NULL,
    day        TEXT NOT NULL,
    title      TEXT,
    author     TEXT,
    reason     TEXT,
    ts         REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_book_curated_day ON book_curated_history(day);
```

## Algorithm

1. **Work-key normalization** — strip `(version N)`, `(dramatic reading)`, `(read by ...)`, `(solo)`, `(group)` suffixes, lowercase, collapse whitespace → `"author·cleanTitle"`
2. **Candidate pool** — personalized (EXPLOIT+EXPLORE via spoken profile) or cold start (top-100 General Fiction)
3. **Exclusion** — drop workKeys in `book_listen_history` ∪ `book_curated_history`
4. **Pick + widening** — date-seeded RNG from pool; if empty, widen: personalized → top-100 → broad LibriVox → any LibriVox → LRU fallback
5. **Persist** — write to `book_curated_history` (day cache + never-repeat ledger)

## Test Plan

### Unit Tests (no network)
- Work-key normalization (8 cases)
- Exclusion logic (5 cases)
- Never-repeat guarantee (3 cases)
- Cold start vs personalized fallback (4 cases)
- Widening ladder (4 cases)
- Daily stability (3 cases)
- Refresh behavior (2 cases)
- Play recording hook (4 cases)
- Database table CRUD (7 cases)

### Integration Tests (real IA)
- Three days → three distinct books, valid covers
- Cold start → General Fiction
- Personalized → author in profile

## Edge Cases
- New user → cold start top-100
- Heavy user exhausted niche → widening ladder → LRU
- Version normalization → different recordings same workKey
- Durable ledgers survive track eviction
- Same-day relaunch → DB cache hit
- Midnight boundary → fresh pick

## Implementation Phases
1. Data Layer — DatabaseService tables + methods
2. Model — BookForYouEntry
3. Service — BookForYouService
4. Store — BookForYouStore
5. Play Hook — PlayerViewModel augmentation
6. UI — ListenView BookForYouSection + asset
7. Tests — Unit + Integration
