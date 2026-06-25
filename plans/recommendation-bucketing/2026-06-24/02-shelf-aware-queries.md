# Phase 2 — Shelf-aware recommendation queries

## Problem
- Music queries can leak audiobooks (serendipity branch is unscoped).
- Books queries are scoped to *music* collections, so personalized books never
  match → cold-start.

## Current behavior
- `RecommendationsController.fetchMixedRecommendations(musicOnly:booksOnly:)`
  builds queries via `RecommendationQueryBuilder.generateQueries(profile:dateSeed:
  allCollectionIDs:)` where `allCollectionIDs` is always the music collection set.
- Serendipity query: `subject:"A" AND subject:"B" AND mediatype:audio AND
  downloads:[200 TO *]` — no collection scope, no spoken exclusion.
- `buildFallbackQueries` scopes to the same music collections.

## Research signal
- `default_collections.json` is music-only (every entry has `-subject:"spoken word"`).
- The app's spoken-word selector targets `collection:librivoxaudio`
  (`InternetArchiveService`, `SearchQuery`). Decision: books → `librivoxaudio` only.

## Design
Introduce an explicit per-shelf **scope** passed into query generation:

```
enum RecommendationScope {
    case music(collectionIDs: [String])   // music collections from IACollectionStore
    case books                            // collection:librivoxaudio

    var collectionClause: String          // "(collection:a OR collection:b ...)" or "collection:librivoxaudio"
    var exclusionClause: String           // music: " AND NOT collection:librivoxaudio AND NOT subject:\"spoken word\""; books: ""
}
```

`generateQueries(profile:dateSeed:scope:)`:
- exploit/explore: `… AND \(scope.collectionClause)`.
- serendipity: `… AND mediatype:audio AND downloads:[floor TO *] AND
  \(scope.collectionClause)\(scope.exclusionClause)` — now collection-scoped.
- music adds `exclusionClause` to serendipity (belt and suspenders).

`fetchMixedRecommendations(shelf:)` builds the scope:
- music shelf → `.music(extractCollections(IACollectionStore.shared.collections))`,
  spoken queries suppressed.
- books shelf → `.books`, music queries suppressed.

`buildFallbackQueries` takes the same scope.

Keep backward-compatible `allCollectionIDs:` entry point as a thin wrapper that
builds a `.music` scope, so existing tests/signature callers keep working.

## Data-model deltas
None.

## Implementation steps
1. `RecommendationQueryBuilder.swift`: add `RecommendationScope`; add
   `generateQueries(profile:dateSeed:scope:)`; route the legacy
   `allCollectionIDs:` overload through `.music`. Scope every branch incl.
   serendipity.
2. `RecommendationsController.swift`: replace `musicOnly/booksOnly` flags with a
   `shelf` parameter (or keep flags but derive scope); build per-shelf scope;
   thread scope into `buildFallbackQueries`.
3. `MadeForYouShelfStore.swift`: call site passes shelf.

## Testing strategy
- music serendipity query string contains `NOT collection:librivoxaudio` and a
  music collection clause; never bare `mediatype:audio` without a collection.
- books queries contain `collection:librivoxaudio` and never a music collection id.
- empty profile still yields no queries.
- determinism under fixed date seed preserved.

## Open questions
- None blocking.
