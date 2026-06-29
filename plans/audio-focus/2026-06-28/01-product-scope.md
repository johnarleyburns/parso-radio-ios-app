# 01 — Product Scope & Positioning

## Problem
Lorewave currently presents itself as a mixed-audio app (music + audiobooks + lectures + podcasts + ambient). We are narrowing it to spoken word only, with zero user-facing or runtime music.

## Current Behavior
- 3-tab app (`ParsoRadio/Views/RootTabView.swift:9–22`): **Listen / Library / Search**.
- Home order (`ParsoRadio/Views/Listen/ListenView.swift:17–34`): `HomeTopSection` → **`MadeForYouSection` (Music For You)** → `BooksForYouSection` → `ExploreTypeRow` → `FeaturedTodaySection`.
- Explore chips (`ParsoRadio/Core/Models/LibrarySectioning.swift:11–17`): **Music ("Internet Archive Collections")**, Books, Lectures, Podcasts, Ambient.
- Search scopes (`ParsoRadio/ViewModels/SearchViewModel.swift:28–50`): **music (default), albums, audiobooks, podcasts**.
- Welcome card (`ParsoRadio/Views/Listen/HomeSections.swift:46`): "**Music**, audiobooks, lectures, podcasts and ambient sound…".
- Splash tagline (`ParsoRadio/Views/SplashView.swift:34`): "Free audio, forever."

## Research Signal
- The catalog's defensible, license-clean spine is already spoken word: LibriVox (PD), Oxford lectures (CC BY), and a subset of CC/PD podcasts. Music sources (FMA scrape, arbitrary IA collections) carry the highest rights/representation risk and the weakest curation.
- Competitor PD-audio apps (LibriVox players, public-domain audiobook apps) succeed by being unambiguous about catalog provenance. Mixed-music framing dilutes that and creates App Review/legal exposure.

## Design

### In scope (kept / renamed)
- **Books for You** is the sole recommendation shelf (`BooksForYouSection`, LibriVox-only, plays whole works).
- **Search**: Audiobooks + Podcasts scopes (and Lectures only if a lecture search path is deliberately added — see open question Q-2).
- **Explore**: Books, Lectures, Podcasts, Ambient (utility).
- **Item surfaces**: "Book / Chapters", "Series / Lectures", "Episodes" — never "Album / Tracks".
- **Tip jar** (3 consumable tiers) reframed as Lorewave-support only.

### Out of scope (removed)
- Music For You shelf, music recommendations, music taste bucket.
- "Internet Archive Collections" (`default_collections.json`) and arbitrary IA music collections.
- Free Music Archive (`FMAService`) entirely.
- Music search scopes (music, albums); album detail/search behavior for music albums.
- `MusicControls` surface, shuffle/repeat music-only controls, random-album-track advance, add-to-playlist music special-casing.

### Target home order (ASCII)
```
┌─ Listen ───────────────────────────────┐
│ [ Jump back in ]  (horizontal)          │
│                                         │
│ Books for You                           │  ← only recs shelf
│ [card][card][card]  →                   │
│                                         │
│ Explore                                 │
│ ( Books )( Lectures )( Podcasts )( Ambient ) │
│                                         │
│ Featured today                          │
└─────────────────────────────────────────┘
```

### Positioning copy (target)
- Tagline: **"Free listening, forever."** (`SplashView.swift:34`)
- Support: **"Public-domain audiobooks, open lectures, and verified open podcasts. No ads, no login, no tracking."** (`HomeSections.swift:46`, About/Terms, StoreKit settings copy)
- Vocabulary: audiobooks, lectures, chapters, episodes, books, spoken word. Avoid "music", "albums", "tracks" wherever user-facing text means chapters/episodes. ("track" may remain in neutral internal/playlist-count copy where it is genuinely a generic item — flagged per-string in P3/P6.)

## Data-Model Deltas
None in this doc (positioning only). Model deltas live in `02-code-removal.md` and are summarized in `04-verification-rollout.md`.

## Implementation Steps
Covered per-subsystem in `02-code-removal.md`; copy in `03-rights-privacy.md` (privacy/terms/StoreKit) and P3/P6.

## Testing Strategy
- Behavior test: search exposes no music/albums scope; default scope is audiobooks.
- Behavior test: recommendations return LibriVox audiobooks only.
- UI smoke (seeded via `-uiTestSeed`): first launch, Listen, Search, Library, Now Playing, Books for You, podcast add, lecture playback render without a music surface.

## Open Questions
- **Q-1 (ambient):** Keep ambient as a non-music utility, or remove it? → decision sheet **D-1**.
- **Q-2 (lecture search):** Add a dedicated Lectures search scope, or leave lectures browse-only? → decision sheet **D-2**.
- **Q-3 ("track" wording):** How aggressively to purge the generic word "track" from neutral copy (playlist counts, "Recently Played")? → decision sheet **D-3**.
