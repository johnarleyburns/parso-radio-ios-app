# Curator Mode — Plan (for review)

**Thesis (the hill we die on):** curated channels stop being *search-based* and
become *explicit, human-approved track lists*. Default-deny: a track plays on a
curated channel ONLY if a human admin explicitly approved it. This is the
"leave out rather than accidentally include" philosophy (CLAUDE.md) taken all
the way — a Lucene query cannot tell a great recording from a bad one; a person
can. An in-app, PIN-gated Curator Mode makes that review efficient, and an
export carries the verdicts out of the app so they can ship to everyone.

---

## 1. THE CRUX: authoring vs. distribution (decide this first)

This is the part most "in-app curation" ideas miss. You review **on your
device**, but the approved list must reach **every user's** curated channels.
Local curation state is not enough — it has to leave your phone and become the
source of truth in the build/release. Two viable models:

- **A. Bundled manifest (recommended, on-brand).** Curator Mode exports an
  approved-list **JSON** per channel; you commit it to the repo as a bundled
  resource (e.g. `Curation/childrens-songs.json`). The app ships it; curated
  channels play from the manifest. *Pros:* no backend, matches the app's
  no-server ethos, reviewable in git, deterministic. *Cons:* changing curation
  needs an app update (CI → TestFlight/App Store).
- **B. Hosted manifest.** The same JSON lives at a static URL you control (e.g.
  `parso.guru/curation/childrens-songs.json`); the app fetches + caches it.
  *Pros:* update curation without an app release. *Cons:* a network dependency
  and a (tiny) hosting responsibility; loses some of the "fully self-contained"
  story.

> Recommendation: ship **A** first (bundled), structure the manifest so it can
> later be served as **B** with no format change. The in-app export is the
> bridge in both cases.

So Curator Mode has two data flows:
1. **Authoring** (your device): IA query → review queue → approve/reject →
   **export** (CSV to read, JSON to commit).
2. **Distribution** (all devices): bundled/hosted **manifest** → channel pool.

---

## 2. Data model

**New SQLite table `curation`** (authoring side, local to the curator's device):
| column | type | notes |
|---|---|---|
| `channel_id` | TEXT | the curated channel |
| `track_id` | TEXT | IA identifier (item) or `identifier/file` (track) |
| `status` | TEXT | `approved` / `rejected` / `pending` |
| `reviewed_at` | REAL | epoch seconds |
| `note` | TEXT? | optional curator note |
| PK | (`channel_id`,`track_id`) | one verdict per track per channel |

Index `(channel_id, status)`. Track metadata already lives in `tracks` — the
candidate fetch saves it there as today, and `curation` just records verdicts.
(Migration: SQLite.swift `createTable(ifNotExists:)` in `DatabaseService.init`,
same pattern as the existing tables; additive, no risk to current data.)

**Manifest format** (distribution side — bundled `Curation/<channelId>.json`):
```json
{
  "channelId": "childrens-songs",
  "updatedAt": "2026-05-29",
  "granularity": "item",          // "item" or "track" (see §6)
  "approved": [
    { "id": "some_ia_identifier", "title": "...", "creator": "...",
      "duration": 212, "note": "vetted nursery rhymes" }
  ]
}
```
Keep title/creator/duration in the manifest so a channel renders instantly
without a metadata round-trip; the playable URL is resolved at runtime (existing
`resolveAudioURL` / per-file streamURL path).

---

## 3. Candidate sourcing (the review queue)

Keep the existing **`IAQueryRegistry`** query per channel — but demote it from
"the curation" to a **candidate generator**. In Curator Mode, opening a channel:
- runs the channel's `iaQuery` (with `sort=random` + pagination / "load more"),
- saves results to `tracks` as today,
- shows each candidate with its current `curation.status` (default `pending`).

This means the existing search work isn't wasted — it becomes the funnel that
feeds human review, exactly the right division of labor.

---

## 4. Curator Mode UI (PIN-gated, in Settings)

- **Entry:** Settings → "Curator" → PIN (a SEPARATE admin PIN from the Kids Mode
  parent PIN). Gate the whole section.
- **Channel list:** the curated channels, each showing progress
  `✔ approved / ✗ rejected / • pending` and a "curation active" switch (§7).
- **Review screen** (per channel): a list of candidates, each row:
  - title · creator · duration · collection badge,
  - **Audition** (play it — reuse the player, like a search-result play),
  - **Approve / Reject** (segmented), optional **note**,
  - status persists immediately to `curation`.
  - **"Load more candidates"** (re-run query / next page / new random sample).
  - Filters: show pending / approved / rejected / all.
  - Optional: "approve all visible" for fast passes, undo.
- **Export** (per channel and/or all): CSV (read) + JSON (commit) — see §5.

Reuse the Kids Mode PIN component (one small reusable PIN alert/view serves both
features with different stored keys).

---

## 5. Export (email — your preference)

- **CSV** (human review): `channel_id,track_id,title,creator,duration,status,reviewed_at,note`.
- **JSON** (the manifest — what you commit): the §2 format, approved-only.
- **Delivery:** `MFMailComposeViewController` with both files attached
  (subject `Lorewave curation — <channel> — <date>`), to your address.
  **Fallback:** if Mail isn't configured, a share sheet
  (`UIActivityViewController`) so AirDrop/Files/any export still works.
- Workflow: email yourself → save the JSON into `Curation/<channelId>.json` in
  the repo → commit → CI ships it. (Or, model B, upload the JSON to the host.)

---

## 6. Granularity — item vs. track (decide)

- **Item-level (recommended default):** approve a whole IA recording/album with
  ONE decision; the existing random-album-track logic then plays its tracks.
  Far less review work; matches how music albums already play. A bad track
  inside a good album is the rare case.
- **Track-level:** approve/reject individual files. Maximum control ("review
  EVERY track"), but for a 20-track album that's 20 decisions.
- **Hybrid (best of both):** approve at item level, with an optional per-item
  "exclude these tracks" list for the occasional dud. The manifest's
  `granularity` field + an optional `excludeFiles` per item supports this.

> Recommendation: hybrid — item-level approval with optional track exclusions.

---

## 7. Playback integration + rollout

- Add `db.fetchApprovedTracks(forChannel:)` (or load the bundled manifest) →
  the **pool** for a curation-active channel.
- **`QueueManager._next`**: for a curation-active curated channel, build the pool
  from the approved manifest instead of `fetchTracks(forChannel:)`. Non-curated
  channels (News/Lectures/Ambient/For You) are untouched. The shadow-recents,
  random-album, and stall logic all still apply on top.
- **Rollout flag per channel** (`curationActive`): until you flip it, the
  channel keeps today's search pool (so channels are never empty mid-review).
  Flip a channel to approved-only the moment its manifest is solid. This lets
  you convert channels **one at a time** over the weeks of review, never
  shipping an empty channel.
- The For-You recommender (which samples curated channels) should sample the
  **approved** pools once active — strictly better recommendations.

---

## 8. Phased delivery

1. **Schema + manifest format** (`curation` table; `Curation/*.json` loader;
   `fetchApprovedTracks`). No UI yet; ship a hand-written manifest for ONE
   channel to prove the runtime path.
2. **QueueManager**: curation-active channels play the approved pool; rollout
   flag; fallback to search pool when inactive. Tests.
3. **Curator Mode UI**: PIN gate, channel list, review screen, audition,
   approve/reject + notes, progress.
4. **Export**: CSV + JSON via Mail/share.
5. **Convert channels** one by one; flip `curationActive` as each is reviewed.

## 9. Effort & risk

- Biggest lift is the **review UI** (#3) and the **manifest round-trip** (#1).
- Low risk to existing playback: curated-pool change is gated behind
  `curationActive`; everything else is additive (new table, new screens).
- The hard product call is **§1 (bundled vs hosted)** and **§6 (granularity)** —
  both flagged for your decision.

## 10. Open questions for you

1. **Distribution:** bundled manifest (app update per change) or hosted JSON
   (live updates, tiny hosting)? — *I recommend bundled first.*
2. **Granularity:** item-level, track-level, or hybrid? — *I recommend hybrid.*
3. **Curator PIN:** separate admin PIN from the Kids parent PIN? — *Yes,
   recommend separate.*
4. **Scope of "curated":** all "Curated" category channels become approved-only,
   or a specific subset first? (Children's first, given Kids Mode?)
5. **Candidate breadth:** keep each channel's current `iaQuery` as the funnel,
   or also let you free-search the whole IA and approve from there?
