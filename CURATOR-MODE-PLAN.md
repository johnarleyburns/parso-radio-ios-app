# Curator Mode — Plan (DECISIONS LOCKED — implementing)

**Thesis (the hill we die on):** curated channels stop being *search-based* and
become *explicit, human-approved track lists*. Default-deny: a track plays on a
curated channel ONLY if a human approved it FOR THAT CHANNEL. A Lucene query
can't tell a great recording from a bad one; a person can. In-app, PIN-gated
Curator Mode makes that review efficient; a JSON export carries the verdicts out
to ship to everyone.

## Decisions (from review)

1. **Distribution: BUNDLED.** Export JSON → commit to repo → app ships it. No
   backend. (Format kept host-serveable later if ever wanted.)
2. **Granularity: HYBRID.** Review per-TRACK (listen in order), with an
   "Approve entire album" shortcut; the manifest may compact an all-approved
   item to item-level, and store per-item track exclusions otherwise.
3. **Curator PIN: SEPARATE** from the Kids parent PIN.
4. **Scope: ALL curated channels**, **children first**.
5. **Candidates: each channel's IA query as the funnel, BROADENED** (cast a
   wider net — manual rejection handles noise, so prefer recall over precision),
   **PLUS in-app search** to manually add tracks/albums to the review set.

## The three sets (per channel — this is the model)

Every verdict is keyed **(channel_id, track_id)** — an item right for one
channel may be wrong for another, so review/accept/reject is **per channel**.

- **Review set** — the queue awaiting a verdict (`status = review`).
- **Approved set** — accepted; this IS the channel's play pool + what exports
  (`status = approved`). *Search-adding never writes here directly.*
- **Reject set** — manually removed (`status = rejected`); **auto-excluded** from
  all future candidate ingestion for that channel.

### Building the review set
- **Preload** from the channel's (broadened) `iaQuery`, expanding multi-file
  items into their tracks so each is auditioned. A candidate enters as `review`
  ONLY if it has no existing verdict for that channel (approved/rejected are
  skipped — reject auto-exclude).
- **Manual add via in-app search**: search IA, add a track or a whole album to
  the **review set** (NOT approved — everything earns its approval by audition).

### The review loop (like playing a playlist)
Curator Mode → pick a channel → the review queue plays **in order**. For the
current track: **Accept** (→approved) · **Reject** (→rejected) · **Skip** (stays
in review, advance) · **Approve entire album** (bulk-accept every track of the
current item). Optional note per verdict.

## Data model

**`curation` table** (authoring, on the curator's device):
| col | type | notes |
|---|---|---|
| `channel_id` | TEXT | curated channel |
| `track_id` | TEXT | `identifier` (single-file item) or `identifier/file` (track) |
| `status` | TEXT | `review` / `approved` / `rejected` |
| `reviewed_at` | REAL | epoch seconds |
| `note` | TEXT? | optional |
| PK | (`channel_id`,`track_id`) | one verdict per track per channel |

Index `(channel_id, status)`. Track metadata stays in `tracks` (candidate
ingest saves it as today); `curation` only records verdicts.

**Bundled manifest** (`ParsoRadio/Curation/curation.json`, ships in the app):
```json
{
  "version": 1,
  "channels": {
    "childrens-songs": {
      "updatedAt": "2026-05-29",
      "approved": [
        { "id": "ident_or_ident/file", "title": "...", "creator": "...",
          "duration": 212, "parentIdentifier": "ident_or_null" }
      ]
    }
  }
}
```
Title/creator/duration travel in the manifest so a channel renders instantly;
the playable URL resolves at runtime (existing resolve / per-file streamURL).

## Playback integration

- `db.fetchApprovedTracks(forChannelId:)` and a `CurationManifest` loader for the
  bundled file.
- **QueueManager**: for a curated channel that HAS a manifest entry, build the
  pool from the **approved** tracks (then the existing shuffle + 30-deep
  shadow-recents + stall logic apply). A channel with no manifest entry keeps
  today's search pool — so conversion is channel-by-channel and no channel is
  ever empty mid-rollout.
- Because approved tracks are explicit (often per-file), the random-album step is
  unnecessary on curated channels — the approved set already names the tracks.
- The For-You recommender samples the **approved** pools once a channel is live.

## Export (email — your workflow)

- **All channels → one JSON** (the manifest format above), attached via
  `MFMailComposeViewController` to your address; **share-sheet fallback** if Mail
  isn't configured. (Optional CSV alongside for eyeballing.)
- At your desk: drop the JSON into `ParsoRadio/Curation/curation.json`, commit,
  CI rebuilds → every user gets the curated set.

## Implementation phases (each its own CI-green commit)

1. **Data layer (START HERE):** `curation` table + verdict methods
   (set/get/counts/approved/rejected-ids/export) + `CurationManifest` Codable +
   bundled-JSON loader. Unit tests on an in-memory DB. *(No UI, no playback
   change yet — lowest risk.)*
2. **Playback pool:** QueueManager uses the bundled manifest's approved pool for
   any curated channel that has one; search-pool fallback otherwise. Tests.
   Ship a hand-written manifest for ONE children's channel to prove the runtime.
3. **Curator Mode UI:** separate PIN gate (Settings → Curator); channel list with
   review/approved/rejected counts; the review loop (audition in order +
   Accept/Reject/Skip/Approve-album + note); search-to-add-to-review.
4. **Export:** all-channels JSON via Mail/share.
5. **Convert channels:** broaden each `iaQuery`, review, ship the manifest —
   children first, then the rest of the Curated category.

## Risks
- Low risk to current playback: the curated-pool swap is gated on a manifest
  entry existing; everything else is additive (new table, new screens).
- Authoring-vs-distribution is solved by the bundled manifest + export round-trip.
- Bundling JSON: confirm XcodeGen includes `ParsoRadio/Curation/*.json` as a
  bundle resource (Phase 1 verifies the load path).
