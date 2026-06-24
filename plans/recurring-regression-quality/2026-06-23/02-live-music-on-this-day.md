# 02 - Live Music On This Day Validation

## Problem

"Live Music on This Day" can display unplayable Internet Archive items, missing images, missing dates, or under-enriched entries without surfacing a clear error. The feature needs a strict candidate contract before anything is published to the Listen tab.

## Current Behavior

Physical files involved:

- `ParsoRadio/Core/Models/LiveMusicEntry.swift`
- `ParsoRadio/Core/Services/API/LiveMusicOnThisDayService.swift`
- `ParsoRadio/Core/Services/API/LiveMusicOnThisDayStore.swift`
- `ParsoRadio/Core/Services/API/InternetArchiveService.swift`
- `ParsoRadio/Views/Listen/ListenView.swift`
- `ParsoRadio/Views/Listen/LiveMusicDetailView.swift`
- `ParsoRadio/Core/Services/Playback/WholeItemController.swift`
- `ParsoRadio/Core/Tests/LiveMusicOnThisDayTests.swift`
- `ParsoRadio/Integration/Tests/LiveMusicOnThisDayIntegrationTests.swift`
- `ParsoRadio/UITests/LiveMusicOnThisDayUITests.swift`

Current observed behavior:

- `LiveMusicOnThisDayService.fetchEntries(for:)` searches `collection:(etree) AND "MM-dd"` and maps search docs into `LiveMusicEntry`.
- `fetchDailyEntry(forceFresh:)` randomly picks from the pool, enriches one candidate, and only checks `hasTitle`.
- If enriched metadata has a date that does not contain today's `MM-dd`, the service caches and returns the original pool item. This can publish a stale or under-enriched item.
- If no tried candidate passes `hasTitle`, the service caches and returns `pool.first` anyway.
- The service does not validate that the item has any playable audio file before publishing it.
- The Listen card's direct play button uses `deps.archiveService.fetchTracksForIdentifier(entry.id)`, but the detail view uses `playerVM.resolveItemParts(identifier:)`, which returns `nil` for single-file items by design.
- The store only publishes `entry` and `isLoading`; it has no `error`, `emptyReason`, or candidate-rejection state.
- UI tests only check that the section/card exists. They do not verify title/date/image/playability contracts.

## Research Signal

- Internet Archive's Metadata Read API returns both item-level `metadata` and file-level `files`, and documents that some fields are optional. Candidate validation must therefore inspect both levels instead of trusting search results.
- IA metadata schema separates item metadata from file metadata. A live recording card needs item fields for display and file fields for playback.
- Existing `InternetArchiveService.fetchTracksForIdentifier(_:)` contains a permissive single-format audio selection policy. Replace it with a shared MP3-only selector used by every playback path.
- A single playable file is valid for playback, even if it is not a "multi-part" item. The current use of `resolveItemParts` in `LiveMusicDetailView` confuses "not multi-part" with "not playable".

## Design

Introduce a validation layer that only publishes valid daily entries.

```
LiveMusicOnThisDayService
  |
  +-- searchEtree(mmdd) -> [CandidateID]
  |
  +-- CandidateValidator.validate(id, mmdd)
        |
        +-- GET /metadata/{id}
        +-- parse item metadata:
        |     title, creator, venue, coverage, date, description
        +-- parse files:
              choose playable audio files using shared MP3-only selector
        +-- verify:
              display name not empty
              date matches today's MM-dd
              playableTracks.count >= 1
              all selected files are MP3 Layer 3 / VBR MP3
        +-- return ValidatedLiveMusicEntry

LiveMusicOnThisDayStore
  state:
    idle
    loading
    loaded(entry)
    empty(message)
    failed(message, retryable)
```

UI contract:

```
Live Music on This Day

loading:
  [default art + spinner] Searching...

loaded:
  [verified art or fallback] Title
  Venue - Location
  June 23, 1977
  [play]

empty/failed:
  [fallback art] No playable live recording found for today.
  [Retry]
```

Important rule: cache only validated entries, keyed by full `yyyy-MM-dd`. Invalid candidates can be cached in-memory for the current refresh so the app does not retry the same bad item repeatedly.

## Data-Model Deltas

No destructive SQLite change is required.

Additive model changes:

- Extend `LiveMusicEntry` with optional fields:
  - `playableTrackCount: Int?`
  - `validatedAt: Date?` or `validatedAtEpoch: Double?`
  - `sourceDate: String?` if `date` is normalized for display.
  - `artworkStatus: ArtworkStatus?` if the validator centralizes placeholder detection.

Because `LiveMusicEntry` is cached in `UserDefaults`, make decoding backward-compatible by giving new fields default values in a custom `init(from:)`, or invalidate old cache keys on decode failure.

Required runtime structure:

- `ValidatedLiveMusicEntry`
  - Contains `entry: LiveMusicEntry` and `tracks: [Track]`.
  - The store can cache tracks for the selected entry for the session to avoid a second metadata fetch on Play.

## Implementation Steps

1. Extract shared MP3-only file selection.
   - Move the selector list and audio-file sorting from `InternetArchiveService.fetchTracksForIdentifier(_:)` into an internal helper, for example `InternetArchiveAudioFileSelector`.
   - Change behavior for all callers to MP3-only. Accept IA formats `VBR MP3`, `128Kbps MP3`, `64Kbps MP3`, `MP3`, and `.mp3` filenames. Reject Ogg, FLAC, M4A, AAC, Opus, WAV, SHN, video containers, and every other non-MP3 format.
   - Apply the same selector to IA search playback, whole-item playback, Made For You, Book For You, Live Music, downloads/cache, and any IA-backed playlist expansion.

2. Add `LiveMusicCandidateValidator`.
   - Input: identifier, expected `MM-dd`, `URLSession`, and the audio selector.
   - Output: validated entry plus playable tracks, or a rejection reason.
   - Reject candidates with no MP3 audio, no usable display name, or a date that does not match the requested day.
   - If metadata title is missing, synthesize a display name from creator plus venue/date. Do not publish creator-only or date-less cards.
   - Treat SHN-only, FLAC-only, Ogg-only, M4A-only, AAC-only, Opus-only, WAV-only, video-only, or metadata-only items as invalid.

3. Fix `LiveMusicOnThisDayService.fetchDailyEntry(forceFresh:)`.
   - Fetch or refresh the pool.
   - Try candidates until one validates or the attempt limit is hit.
   - Do not return `pool.first` after validation failures.
   - Cache only the validated entry.
   - Read the cached validated entry for the same full `yyyy-MM-dd` before randomizing a new pick, unless `forceFresh` is true.

4. Upgrade `LiveMusicOnThisDayStore` to publish a typed state.
   - Keep `entry` compatibility for one transition release, but derive it from state.
   - Add `errorMessage` or `state.empty(message:)` so the UI can show a clear no-result state.

5. Fix the detail view track loader.
   - Replace `playerVM.resolveItemParts(identifier:)` with a live-music playback loader that accepts one or more tracks.
   - Reuse `InternetArchiveService.fetchTracksForIdentifier(_:)` or the validator's cached tracks.
   - Single-file recordings must enable Play All and show one row.

6. Fix the Listen card play path.
   - Use the same validated track list when possible.
   - If tracks are fetched at tap time and fetch fails, show `playerVM.errorMessage` and keep the card in a non-playing state.

7. Centralize artwork fallback.
   - Keep `live-music-default`.
   - If `services/img` returns the IA placeholder or tiny response, use fallback and do not treat it as a feature failure if the rest of the entry validates.

## Testing Strategy

Add tests before changing selection behavior:

- `LiveMusicCandidateValidatorTests`
  - Valid metadata with one MP3 -> accepted.
  - Valid metadata with multiple MP3s -> accepted with ordered tracks.
  - VBR MP3 and MP3 Layer 3 labels -> accepted.
  - SHN-only files -> rejected.
  - FLAC/Ogg/M4A/AAC/Opus/WAV files -> rejected.
  - Metadata-only/no audio files -> rejected.
  - Date mismatch -> rejected.
  - Missing title but creator plus venue/date -> synthesized display name accepted.
  - Missing title and insufficient synthesis fields -> rejected.
  - Missing image/placeholder image -> accepted with fallback artwork status.

- `LiveMusicOnThisDayServiceTests`
  - If first candidate fails validation, service tries the next candidate.
  - If all candidates fail, service returns `nil`/empty state and does not cache `pool.first`.
  - `forceFresh` avoids the last picked valid id when possible.
  - Cached validated entry is reused for the same full `yyyy-MM-dd`.

- `LiveMusicDetailViewModelTests` or extracted loader tests
  - Single-file live item produces one track and enables play.
  - Multi-file live item preserves natural order.
  - Unsupported item produces an error message, not an empty silent list.

- `LiveMusicOnThisDayUITests`
  - Add accessibility identifiers for title, date, artwork, play button, empty/error state.
  - Assert loaded card contains a non-empty title and date or a visible empty/error state.

Integration test:

- Keep `LiveMusicOnThisDayIntegrationTests`, but make it assert that a real fetched entry has `playableTrackCount > 0`, a date matching today's `MM-dd`, and at least one playable URL.

## Settled Decisions

- Candidates without metadata title may be accepted only with a synthesized display name from creator plus venue/date.
- MP3-only is mandatory. Do not select Ogg, FLAC, M4A, AAC, Opus, WAV, SHN, or any other non-MP3 format.
- Daily cache keys use full `yyyy-MM-dd`; search still matches today's `MM-dd`.
- If validation finds no candidates, show the visible empty/error state with retry. Do not hide the section.
