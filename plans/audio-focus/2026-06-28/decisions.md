# Decisions

## Locked (from handoff — do not re-litigate)
1. **Spoken-word-only release.** No user-facing or runtime music functionality.
2. **No built-in unverified podcasts.** Retain only shows with explicit reusable PD/CC licensing; otherwise remove. User-added RSS may remain as a personal subscription feature, not part of the curated catalog.
3. **No IA music collections.** Remove "Internet Archive Collections" + `default_collections.json` from runtime, resources, tests, and project membership.
4. **No FMA.** Delete `FMAService` and all references/labels/fixtures.
5. **No donation-to-Internet-Archive language.** Remove "10% of proceeds", "donate/donating/donation", proceeds-to-IA copy everywhere.
6. **No subscriptions.** No auto-renewable subscriptions exist; remove the false "auto-renewable subscriptions" copy in privacy text. Tip jar (3 consumable tiers) stays as Lorewave-support only.
7. **No destructive DB migration.** Hide/ignore legacy music rows; stop creating new music rows; additive schema only.

## Assumed defaults (from handoff)
- Planning docs under `plans/audio-focus/2026-06-28/`.
- External privacy-policy update lives in `../parsoguru`.
- Tag `pre-audio-focus` at `0ec3d070098d2097925b9016ca5cde020e7fe258`; do not push unless asked.

## Recorded results (verbatim once developer answers)
- **D-1 (2026-06-28):** Keep ambient as a non-music utility. Retain the "Ambient" mode; never label it music; bundled WAVs remain the offline fallback (exempt from the MP3-only policy).
- **D-4 (2026-06-28):** Keep the raw `MediaKind.music` / `ContentType.music` case for legacy `Codable` decode, route it to a hidden/unsupported path, and add a guard test that no *new* content is created as `.music`.
- **Podcast retention bar (2026-06-28):** Strict — retain a built-in podcast only with an explicit Creative Commons or public-domain license (US-gov PD counts). Remove all-rights-reserved and "permissive but unstated" shows.
- **NonCommercial conservatism (2026-06-28):** Of the strict-bar survivors, keep ONLY explicit public-domain built-ins. Drop the 11 verified CC-NonCommercial shows (9 TWiT BY-NC-ND 4.0 + LINUX Unplugged BY-NC 4.0 + Democracy Now! BY-NC-ND 3.0 US) to avoid any NC-vs-tip-jar argument. Net built-in podcasts = the 2 NASA public-domain shows only (`podcast-nasa-curious-universe`, `podcast-nasa-houston`). Q-B: may revisit if the tip jar is reframed/removed.
- **D-2 (2026-06-28):** Lecture search scope = browse-only. Search exposes Audiobooks + Podcasts only (no IA-backed lecture query path exists).
- **D-3 (2026-06-28):** Replace "track" only where it denotes a chapter/episode/lecture; keep neutral generic phrasing ("items", "Recently Played", "played") elsewhere. Per-string map in `05-open-decisions-and-rights-audit.md`.
- **D-5 (2026-06-28):** Add additive `Track.isUserSubscription: Bool = false` + a bundled `podcast_licenses.json` registry; `PodcastRSSService` stops hardcoding `.publicDomain` (uses registry for built-ins, neutral non-catalog state for user feeds).
- **D-6 (2026-06-28):** Compliance is NASA-only now (CC shows dropped). Acknowledge "Courtesy of NASA"; do not imply endorsement; review/replace NASA artwork if it embeds NASA insignia (logos are not PD).
- **Round-2 additions bar (2026-06-28):** Built-in podcast additions accept any **non-NonCommercial** license — PD / CC0 / CC BY / CC BY-SA / CC BY-ND / open-gov (OGL v3.0 / CC BY). NC (CC BY-NC*) and NC-style Crown copyright stay excluded (consistent with dropping the 11 CC-NC shows). This broadens the earlier "PD-only" built-in stance; NC remains excluded either way.
- **Round-2 additions disposition (2026-06-28):** From 11 user-supplied candidates (all given as Apple/landing-page URLs, not RSS feeds): **ADD 5** — `podcast-nasa-small-steps` (PD), `podcast-ipse-dixit` (CC0), `podcast-endless-knot` (CC BY-SA 4.0), `podcast-rpa` (OGL v3.0), `podcast-inside-hmcts` (OGL v3.0); **EXCLUDE 2** — WB-40 (site down / likely NC), CRA Taxology (Crown NC-style); **EXCLUDE 4** (re-verified 2026-06-28 — no working `https` feed found, dropped) — Code for Thought + Open Source Creative (dead sites), Met Éireann + 5 mins with the FMA (JS player only, no RSS, no explicit CC). Net built-in podcasts = **7**. Details/feeds in `05-open-decisions-and-rights-audit.md`.

---

## Open decision sheets (need developer validation)

### D-1 — Ambient
**Question:** Keep ambient (4 channels: Yellowstone NPS-PD, 3 Freesound CC0) as a non-music utility mode, or remove it?
**Recommendation:** Keep, presented as "Ambient" utility, never labeled music. (Bundled WAVs are the offline fallback exempt from the MP3-only policy.)
**Answer:** RESOLVED 2026-06-28 — Keep as non-music utility.

### D-2 — Lecture search scope
**Question:** Add a dedicated Lectures search scope, or leave lectures browse-only (Search = Audiobooks + Podcasts)?
**Recommendation:** Audiobooks + Podcasts only initially; Oxford lectures are browse-only (no IA search path exists today).
**Answer:** RESOLVED 2026-06-28 — browse-only; Search = Audiobooks + Podcasts.

### D-3 — Generic "track" wording
**Question:** How aggressively to purge "track" from neutral copy (playlist "N tracks", "Recently Played", "Tracks you play will show up here")?
**Recommendation:** Replace where it denotes chapters/episodes; allow neutral generic "items"/"played" phrasing elsewhere.
**Answer:** RESOLVED 2026-06-28 — targeted replacement; per-string map in `05-open-decisions-and-rights-audit.md`.

### D-4 — `MediaKind.music` / `ContentType.music` cases
**Question:** Delete the enum cases, or keep raw values for legacy decode only?
**Recommendation:** Keep `case music` raw value for `Codable` decode of legacy rows; route it to a hidden/unsupported path; add a guard test that no *new* content is created as `.music`.
**Answer:** RESOLVED 2026-06-28 — Keep raw case for legacy decode; hide it.

### D-5 — User-feed neutral license state
**Question:** New `LicenseType.userSubscription` case vs `Track.isUserSubscription` boolean?
**Recommendation:** Boolean flag (less invasive, additive).
**Answer:** RESOLVED 2026-06-28 — `Track.isUserSubscription` boolean + bundled `podcast_licenses.json` registry.

### D-6 — NASA / Democracy Now! attribution
**Question:** Exact attribution text + confirm CC BY-NC-ND (no-derivatives) is satisfied by unmodified in-app streaming.
**Answer:** RESOLVED 2026-06-28 — moot for CC shows (all dropped). NASA-only: "Courtesy of NASA", no endorsement, review artwork for NASA insignia.
