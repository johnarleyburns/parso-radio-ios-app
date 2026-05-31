# Customizable Curated Channels — Plan (for review)

> Supersedes the current "Curator Mode" gate. The redesign moves curation from
> a hidden admin flow to a **first-class user feature**: every user can have
> their own custom Curated channels, edit them in place, and import/export
> single-channel definitions. The shipped "Curated" channels become **default
> templates** users can keep, customise, replace, or augment.

## Goals

1. **No more PIN gate** — anyone can curate; their changes are their own.
2. **`+` and `Edit` on the Curated section** in the menu (standard Apple HIG
   `EditButton` / `+` toolbar pair), and a **per-channel edit affordance**
   reached via the channel's own info screen.
3. **Add channel** → pick a name → search Internet Archive → bulk-add results
   to the channel's review queue, with an "N items — proceed?" confirmation.
4. **Edit channel** → enter the per-channel curator surface in place; reorder /
   rename / delete on the list; long-press menu OR an `(i)` info chevron on
   each row (Apple HIG analogue: Apple Music's "..." on a playlist row).
5. **One JSON per channel** instead of the current unified `curation.json` —
   importable / exportable / shareable / inspectable individually.
6. **Built-in defaults** ship as starter templates the user can "fork" the same
   way as a shared file: they pre-populate the channel list but every channel
   is editable.
7. **Import/export single channels** via the share sheet so users can swap
   channel definitions like presets.

## What changes for users (the experience)

- The Main Menu's **Curated** category row now opens a list whose toolbar
  carries `Edit` + `+`. Tapping `+` starts the "new channel" sheet (name →
  search → bulk-add → review). `Edit` puts the list into the Apple HIG edit
  mode (reorder rows, swipe-to-delete, rename inline).
- Each channel row gets a trailing `(i)` chevron → **Channel Info**. The info
  screen carries the existing description + a prominent "Edit Channel
  (Curate)" action that opens the per-channel review screen (today's
  `CuratorReviewView`, refit for in-place use).
- On the per-channel review screen, the user audits the review queue with the
  existing Accept/Reject (and the new approved/rejected filter — folded in as
  part of this redesign). Search adds candidates the same way.
- **Settings → Curator** goes away. The same actions live where the user
  expects them.
- **Long-press a channel row** on the Curated list → quick menu with
  *Curate*, *Rename*, *Duplicate*, *Export…*, *Delete* (Apple HIG: list-row
  context menus).
- **`+` → Import** is offered as an alternative inside the new-channel sheet
  so a friend's exported JSON can become a one-tap new channel.

## Apple HIG anchor (which gestures we use)

- **Toolbar `Edit` + `+`** on a list (`EditButton`, `Image(systemName: "plus")`)
  — same pattern Mail, Reminders, Notes use for top-level lists.
- **Swipe-to-delete** + **`onMove`** in Edit mode for delete/reorder.
- **List row `(i)` chevron** for "info / settings about THIS row" — the same
  affordance as Maps places, Music albums.
- **List row `.contextMenu`** (long-press) for quick actions per row.
- **`.shareSheet(URL)`** for export; **`.fileImporter`** for import.

## Data model

- Drop the shipped, unified `ParsoRadio/Resources/curation.json`.
- Replace with **`ParsoRadio/Resources/curated-channels/*.json`** — one file per
  shipped DEFAULT channel (`curated-channels/guitar-classical.json`,
  `curated-channels/chamber-music.json`, etc.). Each file defines the channel's
  identity AND its approved tracks; it's the same shape exported / imported
  from the app.
- On launch, the app:
  1. Reads each shipped file as a default (always available, never edited in
     place — they live in the bundle which is read-only).
  2. Reads each USER override / addition from
     `Documents/curated-channels/<id>.json` — user wins.
  3. Builds the runtime channel list from the union: any default that hasn't
     been deleted by the user, plus the user's custom ones, in the user's
     saved order.
- One file per channel makes per-channel **export = copy that one file** and
  **import = drop a file in `Documents/curated-channels/`**. Trivial.

Per-channel JSON (extending the existing `CurationManifest.ChannelCuration`):
```json
{
  "version": 1,
  "channel": {
    "id": "guitar-classical",
    "name": "Classical Guitar",
    "icon": "guitars",
    "iaQuery": "<the candidate-generator query, OR null for hand-built only>"
  },
  "updatedAt": "2026-05-31",
  "approved": [
    { "id": "…", "title": "…", "creator": "…",
      "duration": 212, "parentIdentifier": null }
  ],
  "rejected": ["…id…", "…id…"]    // optional — sticky reject set
}
```

The `rejected` list joins the existing DB `curation` rows so the reject set
stays sticky across exports and imports.

## Custom user channels — the bookkeeping

Per-user metadata table or a single JSON manifest in `Documents/`:
- `customChannels: [{id, name, icon, iaQuery, createdAt, isShippedDefault}]`
- `deletedDefaults: [shipped_channel_id, …]` — IDs the user removed from a
  shipped default; on next launch we hide them.
- `order: [channel_id, …]` — the user's drag-reordered list.

A user "deleting" a shipped default just records the id in `deletedDefaults`;
the file stays in the bundle untouched. "Restore Defaults" is a Settings
action that clears `deletedDefaults`.

## UI surfaces (concrete views)

### 1) `CuratedChannelsListView` (replaces today's `ChannelListScreen` for the Curated category only)
- Toolbar: `EditButton` + `+`.
- Rows: channel name + count of approved tracks + `(i)` chevron.
- `.onMove` writes the user's reorder.
- `.onDelete` records in `deletedDefaults` (for shipped) or removes the user
  file (for custom).
- `.contextMenu` per row: Curate / Rename / Duplicate / Export / Delete.

### 2) `NewChannelSheet` (the `+` flow)
- Step 1: name + icon picker (SF Symbols set, like an Apple Reminders list).
- Step 2: paste/edit an optional `iaQuery` (with a "this is the candidate
  generator — leave empty to curate purely by search" footer) OR pick "Import
  from file…" → `.fileImporter` flow.
- Step 3: optional initial search → results → multi-select + **"Add N items
  to the review queue?"** confirmation when the count is > 25.
- Saves the file at `Documents/curated-channels/<new-id>.json`.

### 3) `ChannelInfoView` (existing, extended)
- Adds a prominent "Curate this Channel" button at the top → opens the
  per-channel review screen.

### 4) `CuratorChannelEditView` (today's `CuratorReviewView`, refit)
- Same Audition / Accept / Reject + verdict auto-advance + stop on
  background/disappear.
- Filter picker at the top: Review / Approved / Rejected (today's deferred ask).
- Search-Archive.org-to-add stays the same.
- Export action moves here (exports just THIS channel's JSON).

### 5) Long-press / context menu actions on every Curated row
- **Curate** → opens (4)
- **Rename** → alert with TextField
- **Duplicate** → copy to `<id>-copy` with same iaQuery, empty review/approved
- **Export…** → share sheet with the channel's JSON file
- **Delete** → confirm; record in `deletedDefaults` for shipped channels

## Migration from today's state

Phased, fully backward-compatible:

1. **Phase A — split the manifest.** A migration step at first launch reads the
   existing single `curation.json` (bundled + Documents/) and writes per-channel
   files into `Documents/curated-channels/`. Old paths keep working until
   Phase C clears them.
2. **Phase B — list UI.** Add `CuratedChannelsListView` with Edit + `+`. The
   `+` flow can already create files; Edit mode reorders/deletes; the rows
   still drill into today's `ChannelInfoView`.
3. **Phase C — per-channel curator.** Replace `CuratorReviewView` entry from
   Settings with the in-place "Curate this Channel" button on the channel
   info screen. Delete the old Settings entry + the `CuratorController` PIN
   gate.
4. **Phase D — import/export.** Wire `.fileImporter` (single .json) + share
   sheet on each channel.
5. **Phase E — defaults bundled per-channel.** Ship
   `ParsoRadio/Resources/curated-channels/*.json` populated with the current
   manifest's content; remove the unified file.

Each phase ships as its own CI-gated commit and is testable in isolation.

## Tests (this redesign's new layer)

- `CustomChannelsStoreTests` (Foundation-only): create/load/save/delete,
  `deletedDefaults` semantics, per-channel JSON round-trip.
- `ChannelOrderTests`: user reorder persists; shipped + custom mix correctly.
- `ImportExportTests`: a valid file round-trips; an invalid one is rejected
  cleanly; an importing-an-existing-id flow asks "Replace or Duplicate?".
- `CuratorBulkAddConfirmTests`: the "Add N items?" threshold is exercised at
  N=10, 50, 200.
- `NavigationAuditTests` extension: the new list works in Kids Mode (still
  hidden), and the PIN gate's absence doesn't expose anything new to a kid.

## Open questions (please weigh in)

1. **Per-channel icon set** — let the user pick from a curated SF Symbols set,
   or arbitrary system symbol names by text input? *(Recommend: curated set.)*
2. **Default-channel "Restore"** — show in Settings, or always available as a
   row at the bottom of the Curated list? *(Recommend: Settings.)*
3. **Conflict on import** — if `<id>.json` already exists, do we ask
   "Replace existing?" or "Duplicate with new id?"? *(Recommend: present both
   options, default Duplicate to avoid accidental loss.)*
4. **Sharing the same channel id** — should two users' "guitar-classical"
   exports be importable side-by-side, or always considered the same channel?
   *(Recommend: same id = same channel; Duplicate when the user wants two.)*
5. **iaQuery editability after creation** — let the user freely rewrite the
   IA query post-hoc, or treat it as a creation-time choice? *(Recommend:
   editable any time; query is just the candidate generator.)*

## Risks

- **Migration safety** — a fresh user gets the shipped defaults; an existing
  user gets their unified manifest split. We must NEVER drop their approved
  tracks during the split.
- **Apple HIG** — the per-row `(i)` chevron + `.contextMenu` combo is the most
  ambiguous bit; prototype the row early and iterate.
- **JSON-as-import-format** vs Files-app friction — the .json file imports
  via "Open in… Lorewave" on iOS. Should work via Quick Actions; verify on
  device.

## Effort estimate (rough phased shipping)

- Phase A (migration): 1 commit.
- Phase B (list + `+`): 1–2 commits.
- Phase C (in-place curator, remove PIN gate): 1–2 commits.
- Phase D (import/export): 1 commit.
- Phase E (per-channel bundled defaults): 1 commit + content migration.

Total ≈ 6 commits; each independently verifiable in CI. The biggest UX value
lands in Phases B and C — the user gets `+` and `Edit` and inline curation
without the PIN gate.
