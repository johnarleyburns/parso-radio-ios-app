# Pre-Build Curation Plan

## Goal

Pre-fill shipped curated channel JSONs with approved track entries so new users
get a curated starting pool immediately — no blank-slate cold start.

## Current State

Each shipped curated channel has a JSON file at
`ParsoRadio/Resources/curated-channels/<channel-id>.json`. These files define
channel metadata (name, icon, iaQuery) plus optional `approved` and `rejected`
arrays. Currently `approved` is empty for all channels.

On first launch:
1. `loadBundledDefaults()` copies the bundled JSON to `Documents/curated-channels/`
2. `importBundledCurationsIfNeeded(db:)` reads `approved` from the per-channel
   JSON and writes `setCuration(status: "approved")` rows to SQLite — but ONLY
   if the DB has zero verdicts for that channel (unclaimed guard)

Once a user approves or rejects ANY track in a channel, the DB has verdicts and
the JSON is **never consulted again** for that channel.

## Design

### Phase 1 — Seed the approved arrays

For each curated channel we want to pre-seed, add approved track entries to the
bundled JSON. Each entry needs at minimum:

```json
{
  "id": "<IA-identifier>",
  "title": "<Track title>",
  "creator": "<Artist/Author>",
  "duration": <seconds>,
  "parentIdentifier": "<parent-IA-item>"
}
```

Example for `ancient-greece.json`:

```json
{
  "version": 1,
  "channel": { ... },
  "updatedAt": "2026-06-11",
  "approved": [
    {
      "id": "republic_plato_1234",
      "title": "The Republic",
      "creator": "Plato",
      "duration": 37200,
      "parentIdentifier": "republic_plato_librivox"
    }
  ],
  "rejected": []
}
```

A track in `approved` does NOT need to already exist in the tracks table —
`importBundledCurationsIfNeeded` writes curation rows directly to the curation
table. When the IA query fetches tracks later, matching trackIds join against
these pre-written verdicts.

### Phase 2 — Selecting which tracks to pre-approve

Options for populating the `approved` arrays:

**A. Manual curation (recommended for small channels)**
- Run the app locally, curate a channel, export the JSON via "Export this
  Channel" in ChannelInfoView
- Copy the `approved` entries from the exported JSON into the bundled JSON

**B. Automated via merge-curation CLI**
- Extend the existing `merge-curation` CLI (used for merging exported JSONs
  into defaults) to also accept a `--seed` flag that creates empty `approved`
  arrays with entries from a reference export

**C. Query-based seeding**
- Run the IA query for a channel, fetch all matching tracks, filter by quality
  heuristics (duration > 60s, known format, not flagged), auto-approve the top N
- Write a script that does this per-channel and outputs JSON

### Phase 3 — The unclaimed guard remains

`importBundledCurationsIfNeeded` already only imports for channels where the DB
has zero verdicts. This means:
- **New users** get the pre-seeded pool on first launch
- **Existing users** who have already curated a channel keep their own verdicts
- **Reset** (Restore Factory Defaults) clears DB verdicts, then the next launch
  re-imports the pre-seeded entries

No changes needed to `importBundledCurationsIfNeeded` — the current logic
handles this correctly.

### Phase 4 — Future: per-channel seeding depth

Consider a `"seedDepth"` key in the channel JSON:

```json
{
  "seedDepth": 50
}
```

If present, the channel auto-approves the first N tracks returned by its IA
query that pass basic quality gates. The pre-written `approved` entries from the
JSON take precedence, and `seedDepth` fills the gap up to N tracks total.

This avoids manually listing hundreds of IDs in the JSON while still ensuring a
minimum pool size.

### Phase 5 — Refresh strategy

When we ship new pre-seeded entries in an app update:
- Existing users with verdicts are NOT affected (unclaimed guard)
- New users get the updated pool
- Users can "Restore Factory Defaults" from the channel context menu to clear
  their verdicts and get the updated pre-seeded pool on next launch

### Implementation order

1. Pre-Seed all audiobook channels, as these are pre-curated by librivox and have acceptible quality
2. Curate them locally, export JSONs
3. Copy `approved` entries into the bundled JSONs in the Xcode project
4. Build & test: fresh install → verify pre-seeded tracks appear in the curator
5. Once validated, seed remaining channels iteratively

### Files affected (Phase 1 only)

| File | Change |
|------|--------|
| `ParsoRadio/Resources/curated-channels/*.json` | Add `approved` entries |
| `CustomChannelsStore.swift` | No code changes needed |
| `CurationTests.swift` | Add test: fresh DB → pre-seeded verdicts present |

No code changes to the import pipeline — the existing `importBundledCurationsIfNeeded`
already reads `approved` from the per-channel JSON and writes curation rows.
The only work is populating the JSON files with high-quality track entries.

---

**Status: Awaiting review. Please confirm approach before I implement.**
