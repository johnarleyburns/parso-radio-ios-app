# Curation Metadata Enrichment Plan

## Overview

Enrich approved curated channel tracks with metadata from MusicBrainz, Wikidata, and
Cover Art Archive. Results cached locally in SQLite and exported with curation JSON
so channel quality improves over time through repeated enrichment passes.

## 1. Data Model

### New SQLite Table: `track_metadata`

```sql
CREATE TABLE track_metadata (
    track_id       TEXT PRIMARY KEY,
    -- MusicBrainz IDs
    mb_recording_id   TEXT,
    mb_work_id        TEXT,
    mb_artist_id      TEXT,
    mb_release_id     TEXT,
    -- Enriched fields
    composer          TEXT,
    composer_mbid     TEXT,
    performer         TEXT,
    work_title        TEXT,
    catalog_number    TEXT,
    genre_tags        TEXT,   -- JSON array
    duration_ms       INTEGER,
    recording_date    TEXT,
    -- Image URLs
    composer_portrait_url TEXT,
    album_art_url         TEXT,
    track_art_url         TEXT,
    -- Metadata
    enriched_at       REAL,  -- timestamp of last enrichment
    enrichment_source TEXT   -- "musicbrainz", "wikidata", "manual"
);
```

### Track Model Additions

Add optional fields to `Track`:
- `metadata: TrackMetadata?` — loaded on-demand from DB

## 2. MetadataEnrichmentService

### API Endpoints Used

| Source | Endpoint | Rate Limit | What We Get |
|--------|----------|-----------|-------------|
| MusicBrainz | `/ws/2/recording?query=...` | 1 req/sec | recording MBID, duration, release MBID |
| MusicBrainz | `/ws/2/work/{mbid}?inc=artist-rels` | 1 req/sec | composer name, work title, catalog |
| MusicBrainz | `/ws/2/artist/{mbid}?inc=url-rels` | 1 req/sec | Wikidata Q-ID, life dates, type |
| Wikidata | `/wiki/Special:EntityData/{qid}.json` | No limit | composer portrait (P18), birth/death |
| Cover Art Archive | `/release/{mbid}/front-500` | No limit | 500px album art |

### Enrichment Flow (per track)

```
1. Extract creator + title from IA track
2. Search MusicBrainz: recording:"title" AND artistname:"creator"
3. If match found:
   a. Store recording MBID, duration
   b. Fetch work → composer name + MBID
   c. Fetch artist → Wikidata Q-ID
   d. Fetch Wikidata → composer portrait URL
   e. Fetch Cover Art Archive → album art URL (if release MBID exists)
4. If no MusicBrainz match (LibriVox, obscure tracks):
   a. Try Wikidata direct lookup for author/composer name → portrait URL
5. Store all results in track_metadata table
6. Mark enrichment timestamp
```

### Caching Strategy

- One enrichment pass per track; re-enrichment only when user manually triggers
- SQLite is the cache; no in-memory duplication
- MusicBrainz rate limit handled via `Task.sleep(nanoseconds: 1_100_000_000)` between requests
- Wikidata and Cover Art Archive have no rate limits — fetched without delay

## 3. Curation Screen UI: "Run Metadata Queries"

### Location

`CuratorChannelEditView` — a toolbar button or section button labelled "Run Metadata Queries"

### UX Flow

1. User taps "Run Metadata Queries"
2. Confirmation alert: "This will query MusicBrainz for metadata on all APPROVED tracks. It may take a few minutes. Continue?"
3. On confirm:
   a. Fetch all approved tracks for this channel from DB
   b. Filter to tracks NOT yet enriched (no entry in `track_metadata` OR enriched before cutoff)
   c. Begin background enrichment with progress

### Progress Display

- Inline progress view replaces the track list temporarily
- Shows: `ProgressView(value:completed, total:total)` bar
- Text: "23 of 133 approved tracks enriched"
- Each track processes ~1.2 seconds (1 sec rate limit + overhead)
- 133 tracks ≈ 2.5 minutes
- Status persists as long as the view is on screen (foreground only)
- User can navigate away and come back; progress continues as long as app is foregrounded
- If view is dismissed and re-opened, previously enriched tracks are skipped (idempotent)

### State Management

```swift
@State private var enrichmentProgress: (completed: Int, total: Int)?
@State private var isEnriching = false
@State private var enrichmentTask: Task<Void, Never>?
```

## 4. Track Popup: Show All Metadata

### Current State

The curator edit view shows tracks in review/approved/rejected lists. Tapping a track currently does nothing (or plays it).

### New Behavior

Tapping a track opens a popup/sheet showing:
- **Artwork row**: Track art → Album art → Composer portrait → Channel image → Default
- **Title**: Track title (large)
- **Artist/Performer**: IA creator field
- **Composer**: From enrichment (if available)
- **Work**: Canonical work title (if available)
- **Duration**: From enrichment or IA
- **Genre tags**: From enrichment (if available)
- **Recording date**: From enrichment (if available)
- **MusicBrainz IDs**: Linked to musicbrainz.org (tappable)
- **Source**: Internet Archive (with link)

### Implementation

New view: `TrackMetadataSheet` — a sheet presented from the curator row tap.

## 5. Artwork Fallback Chain

### Priority Order (highest to lowest)

1. **Track-specific image** — `track_metadata.track_art_url` or IA item thumbnail
2. **Album art** — `track_metadata.album_art_url` from Cover Art Archive
3. **Composer portrait** — `track_metadata.composer_portrait_url` from Wikidata
4. **Channel image** — `channel.imageURL` (user-set or podcast artwork)
5. **App default** — `Image(systemName: channel.icon)` on gradient background (current behavior)

### Implementation Location

`ArtworkService.artwork(for:)` — updated to check enrichment cache first, then fall through the chain.

`NowPlayingScreen` artwork background — uses the same `ArtworkService` chain.

## 6. Curation JSON Export/Import with Metadata

### Export Format

Add a `metadata` object to each approved entry:

```json
{
  "id": "78_sonata-no-1_alirio-diaz_gbia7003162",
  "title": "Asturias",
  "creator": "Andres Segovia",
  "duration": 387.0,
  "parentIdentifier": null,
  "metadata": {
    "composer": "Isaac Albéniz",
    "composerMBID": "0a46cf2a-61bd-447d-b8fd-a2b32eb20282",
    "performer": "Andrés Segovia",
    "workTitle": "Suite española no. 1, op. 47: V. Asturias (Leyenda)",
    "genreTags": ["classical", "spanish", "guitar"],
    "recordingDate": "2021-03-05",
    "composerPortraitURL": "https://upload.wikimedia.org/...",
    "albumArtURL": "https://coverartarchive.org/..."
  }
}
```

### Import

The `CustomChannelsStore.importChannel(from:)` parses the JSON and:
1. Creates the channel if not exists
2. Imports approved/rejected track IDs
3. Imports metadata into `track_metadata` table
4. Triggers `LiveCurationStore.reload()`

### CLI Tool Update

The `merge-curation` CLI tool (if exists) should also parse and merge the `metadata` field when updating bundled curation JSON files.

## 7. File Changes Summary

| File | Action | Lines |
|------|--------|-------|
| `Core/Models/TrackMetadata.swift` | New model | ~30 |
| `Core/Services/Storage/DatabaseService.swift` | Add track_metadata table + CRUD | ~100 |
| `Core/Services/Metadata/MetadataEnrichmentService.swift` | New service | ~250 |
| `Views/CuratedChannelsListView.swift` | Progress UI + button | ~80 |
| `Views/TrackMetadataSheet.swift` | New popup view | ~120 |
| `Core/Services/Metadata/ArtworkService.swift` | Artwork fallback chain | ~60 |
| `Core/Services/CustomChannelsStore.swift` | Export/import metadata | ~50 |
| `Views/iPodView.swift` | Artwork chain in NowPlayingScreen | ~20 |
| `Utilities/Protocols.swift` | DB protocol additions | ~20 |
| **Total** | | ~730 |

## 8. Implementation Order

1. **TrackMetadata model + DB table** — foundation
2. **MetadataEnrichmentService** — core engine
3. **Curation UI button + progress** — user-facing
4. **Track popup metadata sheet** — user-facing
5. **Artwork fallback chain** — user-facing
6. **Export/Import** — data portability
7. **Tests** — validate enrichment + fallback
8. **Build, test, push**
