# Phase 4 — Favorites in Search

**Problem.** A book found in Search cannot be favorited without playing it.

**Current behavior.** `FavoriteButton` lives only in player controls. `ItemDetailView` has Play/View-on-IA only; search rows are plain buttons.

**Design.**
```
ItemDetailView header ── Favorite toggle (id "itemdetail.favorite")
   favorites.toggle(track: representativeTrack, channel:nil,
                    mediaKind: kind==.book ? .audiobook : .music)
SearchView row .swipeActions ── "Favorite" (id "search.result.favorite.<id>")
```
Representative track for a book = synthesized Track with `parentIdentifier == identifier` so `favoriteID(for:.book) == identifier`.

**Data-model deltas.** None.

**Implementation steps.**
1. `ItemDetailView`: `@EnvironmentObject favorites`; favorite button + state.
2. `SearchView`: row swipe action using the row's resolved `ItemKind`.
3. Helper to synthesize a representative Track from a `ResultGroup` + kind.

**Testing.** UI: book detail shows `itemdetail.favorite`; row exposes the swipe favorite. Unit: toggling a `.book` favorite persists `FavoriteKind.book` keyed by identifier.

**Open questions.** Albums favorite as `.track` (music) per existing `FavoriteKind(mediaKind:)`.
