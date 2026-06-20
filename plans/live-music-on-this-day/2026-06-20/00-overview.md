# Live Music on This Day — Restoration Plan

## Overview

Restore the "Live Music on This Day" feature that was removed in commits `8db2fff` and `26d3852` (June 19, 2026). The feature fetches a random live concert recording from Internet Archive's `etree` collection matching today's month-day (MM-DD), displays it as a fixed-height card on the Listen tab, and supports opening a detail view or playing all tracks immediately.

## Key Design Decisions (from developer Q&A)

- **Card height**: 72pt fixed (`frame(height: 72)`) — consistent with Jump Back In proportions
- **Fallback image**: Bundled PNG asset `live-music-default` at 1x/2x/3x scales (56×56, 112×112, 168×168px)
- **Detail view**: Shows full album with prominent "Play All" button, track list, add-to-playlist
- **Image verification**: `VerifiedThumb` pattern — async size check with < 2KB threshold to detect IA "notfound.png"

## Architecture

```
UserDefaults (24h pool cache + single entry cache)
     ↑
LiveMusicOnThisDayService  ←→  https://archive.org/advancedsearch.php
     |                           (etree collection, date-filtered, 50 rows)
     ↓                           + https://archive.org/metadata/{id} (enrichment)
LiveMusicOnThisDayStore (@MainActor ObservableObject)
     |
     ↓
ListenView
     ├── LiveMusicSection (fixed 72pt card with split left/right taps)
     │     ├── Left tap → LiveMusicDetailView sheet
     │     └── Right tap → playAlbumTracks() → miniplayer
     └── LiveMusicDetailView (full album sheet with Play All, track list)
```

## Files

| # | File | Action |
|---|------|--------|
| 1 | `ParsoRadio/Core/Models/LiveMusicEntry.swift` | Create |
| 2 | `ParsoRadio/Core/Services/API/LiveMusicOnThisDayService.swift` | Create |
| 3 | `ParsoRadio/Core/Services/API/LiveMusicOnThisDayStore.swift` | Create |
| 4 | `ParsoRadio/Views/Listen/LiveMusicDetailView.swift` | Create |
| 5 | `ParsoRadio/Views/Listen/ListenView.swift` | Modify |
| 6 | `ParsoRadio/Resources/Assets.xcassets/live-music-default.imageset/` | Create |
| 7 | `ParsoRadio/Core/Tests/LiveMusicOnThisDayTests.swift` | Create |
| 8 | `ParsoRadio/Integration/Tests/LiveMusicOnThisDayIntegrationTests.swift` | Create |
| 9 | `ParsoRadio/UITests/LiveMusicOnThisDayUITests.swift` | Create |

## Phased Rollout

| Phase | Branch | Contents |
|-------|--------|----------|
| 1 | `feature/live-music-model-service` | Model + Service + Store + Unit tests |
| 2 | `feature/live-music-views` | Asset + DetailView + ListenView changes + Integration tests |
| 3 | `feature/live-music-uitests` | UI tests + polish |
