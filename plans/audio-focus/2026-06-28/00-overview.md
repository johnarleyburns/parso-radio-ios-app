# Audio Focus — Spoken-Word-Only Conversion (Overview)

**Date:** 2026-06-28
**Starting HEAD / safety tag:** `pre-audio-focus` → `0ec3d070098d2097925b9016ca5cde020e7fe258` (verified == HEAD; not pushed)
**Goal:** Convert Lorewave from a mixed-audio app into an audiobook / lecture / podcast (spoken-word) app with **no user-facing or runtime music functionality**.

---

## Raw Notes / Design Principles

- **Spoken-word only.** Catalog = LibriVox public-domain audiobooks, verified Oxford open lectures, and rights-verified open podcasts. Ambient stays only as a non-music utility (see decision sheet D-1).
- **No destructive DB migration.** The SQLite `tracks` and `track_play_history` tables are the source of truth and must remain readable. Legacy music rows are *hidden/ignored*, never deleted. We stop *creating* new music rows.
- **Additive schema only**, per AGENTS.md. No column drops, no row deletes outside the existing channel-filtered prune paths.
- **Rights first.** A built-in source ships only if its reuse rights are verified PD/CC and compatible with in-app streaming + presentation. "Public RSS availability" is *not* a license.
- **Copy must match the app.** Public (`../parsoguru`) + in-app privacy/terms/StoreKit copy must describe exactly what ships. Remove music, FMA, albums, subscriptions, "10% of proceeds", and donation-to-Internet-Archive language.
- **Tip jar stays**, framed only as optional support for Lorewave development/hosting.

## High-Level Roadmap (one branch + PR per phase; see `04-verification-rollout.md`)

| Phase | Title | Plan Steps | Depends on |
|------|-------|-----------|------------|
| P0 | Tag + plan docs (this session) | 1, 2 | — |
| P1 | Remove music recommendation surfaces | 3 (recs), 5 | P0 |
| P2 | Remove IA music collections + FMA | 3 (collections), 4 (FMA) | P0 |
| P3 | Search + UI language → spoken-word | 3 (search), 9 (partial) | P1, P2 |
| P4 | Player/runtime media model cleanup | 4 | P1, P2, P3 |
| P5 | Rights audit + podcast licensing | 6 | P0 |
| P6 | Privacy/terms/StoreKit/docs copy + manifest | 7, 8, 9, 10 | P1–P5 |
| P7 | Verification: source guards + behavior + UI | Test Plan | P1–P6 |

## Cross-Cutting Decisions (see `decisions.md`)

Locked from the handoff: spoken-word-only release; no built-in unverified podcasts; no IA music collections; no FMA; no donation-to-Internet-Archive language; no subscriptions (none exist — remove false copy); no destructive DB migration.

## Document Map

- `01-product-scope.md` — what the app is/isn't, surfaces kept vs removed, copy/positioning.
- `02-code-removal.md` — exact files/lines for every removal, grouped by subsystem, with the spoken-word-safe replacement behavior.
- `03-rights-privacy.md` — per-podcast rights audit framework + licensing fixes + privacy manifest + public/in-app copy deltas.
- `04-verification-rollout.md` — schema-delta summary, migration-safety guarantees, phased rollout table, full test plan, acceptance criteria.
- `decisions.md` — locked decisions (verbatim) + open decision sheets.
- `current_state.md` — live implementation tracker.

## Key Grounding Facts (from codebase audit, 2026-06-28)

- `Channel.defaults` (`ParsoRadio/Core/Models/Channel.swift:134–714`) = **78 channels**: 3 For You (`for-you`, `music-for-you`, `books-for-you`), 18 Oxford lectures, 32 podcasts, 21 LibriVox, 4 ambient.
- The only music IA-query is `music-for-you` in `ParsoRadio/Resources/ia_queries.json:2–8`; the other 22 entries are LibriVox/spoken.
- `ParsoRadio.storekit` has **zero subscriptions** — only 3 consumable tips. Privacy copy that mentions "auto-renewable subscriptions" is already false.
- `PodcastRSSService.swift:142` hardcodes `license: .publicDomain` for **every** podcast track — the central rights bug.
- `PrivacyInfo.xcprivacy` declares only `NSPrivacyAccessedAPICategoryUserDefaults` (CA92.1); FileTimestamp + DiskSpace reasons are missing despite usage in `ArtworkService`, `LocalFileImportService`, `CacheManager`, `OfflineDownloadService`.
