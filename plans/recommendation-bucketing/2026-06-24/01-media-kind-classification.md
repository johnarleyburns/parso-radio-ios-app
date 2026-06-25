# Phase 1 — Media-kind classification core

## Problem
Audiobook plays are seeded into the *music* taste bucket because the bucket is
derived from `track.mediaKind(in: channel)` and the seeding paths pass
`channel: nil` (backfill) or a music-defaulting channel.

## Current behavior
- `TasteProfileStore.seedFromTrack(_:channel:)` → `track.mediaKind(in: channel)`
  → `bucketFor(kind)`.
- `Track.mediaKind(in:)` returns `.music` whenever `channel == nil` for IA tracks.
- Backfill: `MadeForYouShelfStore.ensureTasteBackfillIfNeeded()` calls
  `db.fetchRecentlyPlayedTracksForTasteBackfill` (drops channel) then seeds with
  `channel: nil`.
- A `fetchRecentlyPlayedWithChannel(limit:)` helper already exists in
  `DatabaseService` (returns `(track, channelId)` pairs) but is unused by backfill.

## Research signal
- Registry tracks (music IA + LibriVox) are stamped `pmreg::<channelId>` via
  `InternetArchiveService.fetchTracks` → `Track.stamped`. LibriVox channel ids are
  `lv-*`, lectures `oxford-*` (also `source == "oxford_lectures"`), podcasts
  `podcast-*`/`news-*` (also `source == "podcast"`).
- `Channel.defaults.first { $0.id == channelId }` resolves a registry channel.
- A spoken channel's `Channel.mediaKind` is authoritative; the generic `for-you`
  channel and `direct`/playlist contexts default to `.music`.

## Design
Add a channel-free classifier and make seeding/backfill prefer authoritative
spoken-channel context, else fall back to track signals.

```
extension Track {
    var inferredMediaKind: MediaKind {
        if source == "podcast" { return .podcast }
        if source == "oxford_lectures" { return .lecture }
        let stamps = tags.map { $0.hasPrefix("pmreg::") ? String($0.dropFirst(7)) : $0 }
        if stamps.contains(where: { $0.hasPrefix("lv-") }) { return .audiobook }
        if stamps.contains(where: { $0.hasPrefix("oxford-") }) { return .lecture }
        if stamps.contains(where: { $0.hasPrefix("podcast-") || $0.hasPrefix("news-") }) { return .podcast }
        return .music
    }
}
```

Bucket resolution (used by `seedFromTrack`):
```
let kind: MediaKind
if let channel, channel.mediaKind != .music { kind = channel.mediaKind }
else { kind = track.inferredMediaKind }
```
Rationale: a non-music channel is authoritative (Audiobooks/Lectures/Podcast);
a music channel / nil / `for-you` / `direct` defers to track signals, so a
LibriVox track stamped `pmreg::lv-*` is still classified `.audiobook`.

Channel-aware backfill: iterate `fetchRecentlyPlayedWithChannel`, resolve the
channel by id (`Channel.defaults`), and seed with it.

## Data-model deltas
None. Pure logic; uses existing columns/tables.

## Implementation steps
1. `Core/Models/MediaKind+Resolve.swift`: add `Track.inferredMediaKind`.
2. `Core/Services/Storage/TasteProfileStore.swift`: change `seedFromTrack` bucket
   resolution to the rule above.
3. `Core/Services/Playback/MadeForYouShelfStore.swift`: backfill uses
   `fetchRecentlyPlayedWithChannel`, resolves channel, seeds with it.

## Testing strategy
- `inferredMediaKind`: `lv-*`-stamped IA track → `.audiobook`; plain music IA →
  `.music`; `source=="podcast"` → `.podcast`; `source=="oxford_lectures"` →
  `.lecture`.
- `seedFromTrack(channel: nil)` with an `lv-*`-stamped track seeds the **spoken**
  bucket; a plain IA music track seeds **music** (preserves existing tests).
- Backfill: history with an Audiobooks channel id seeds spoken; a music channel
  id seeds music.

## Open questions
- Books played from the unified `for-you` channel (mixed shelf) recorded under
  `for-you`/`direct` with a `pmreg::for-you` stamp cannot be distinguished from
  music by track signals. The primary Books surface records `books-for-you`
  (`.spokenWord`), so this affects only the mixed channel. Accepted for now.
