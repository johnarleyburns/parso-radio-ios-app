# Current State — Audio Focus (Spoken-Word-Only)

**Last updated:** 2026-06-28
**Safety tag:** `pre-audio-focus` → `0ec3d070098d2097925b9016ca5cde020e7fe258` (created, verified == HEAD, **not pushed**).

## Phase status
| Phase | Status | Notes |
|---|---|---|
| P0 — Tag + plan docs | **DONE** | Tag created; this docs set written, grounded in 2026-06-28 codebase audit. No app code changed yet. |
| P1 — Music recs removal | NOT STARTED | |
| P2 — IA collections + FMA | NOT STARTED | |
| P3 — Search + UI language | NOT STARTED | |
| P4 — Player/media model | NOT STARTED | |
| P5 — Rights + podcast licensing | AUDIT DONE; CODE NOT STARTED | Original audit: 2 keep (NASA PD) / 30 remove. Round-2 additions: +5 verified (NASA Small Steps PD, Ipse Dixit CC0, Endless Knot CC BY-SA, RPA + Inside HMCTS OGL v3.0), 2 excluded, 4 dropped (no usable feed on re-verification). **Net built-in podcasts = 7.** See `05-open-decisions-and-rights-audit.md` |
| P6 — Copy/privacy/docs | NOT STARTED | |
| P7 — Verification | NOT STARTED | |

## Completed work
- Verified clean working tree at starting HEAD.
- Created tag `pre-audio-focus`.
- Audited every subsystem the conversion touches (recs, media model/player, sources/catalog, search/UI, copy/docs/compliance) with exact file:line references; results captured in `02-code-removal.md` and `03-rights-privacy.md`.
- **All decision sheets resolved** (D-1…D-6) and recorded verbatim in `decisions.md`.
- **P5 podcast rights audit complete** — all 32 built-ins verified against primary sources; verdict (2 keep / 30 remove) + registry design + D-2/D-3/D-5/D-6 resolutions in `05-open-decisions-and-rights-audit.md`.

## Decisions (all resolved 2026-06-28)
- D-1: keep ambient as non-music utility.
- D-4: keep `MediaKind.music` raw case for legacy decode; hide it.
- D-2: lecture search = browse-only; Search = Audiobooks + Podcasts.
- D-3: targeted "track" replacement (per-string map in doc 05).
- D-5: `Track.isUserSubscription` + `podcast_licenses.json` registry.
- D-6: NASA-only compliance ("Courtesy of NASA"; review artwork for insignia).
- Podcast bar: strict (explicit CC/PD), then conservative (PD only) → **built-ins = 2 NASA shows**; 30 removed (incl. 11 verified CC-NC shows dropped for tip-jar conservatism).
- Round-2 additions (non-NC bar): +5 verified built-in podcasts → **net 7**; 2 excluded (WB-40, CRA Taxology), 4 dropped on re-verification — no working https feed (Code for Thought, Open Source Creative, Met Éireann, NZ FMA).

## Known gaps / blockers
- No app code changed yet — all of P1–P7 is implementation pending.
- Open product polish: Q-A (surface "add your own feeds" given only 2 built-in podcasts), Q-B (revisit dropped CC-NC shows if tip jar reframed).

## Verification results
- Tag/HEAD match: PASS.
- Podcast licenses: verified via primary sources (twit.tv/about/license, linuxunplugged.com, democracynow.org transcript footer, nasa.gov media guidelines, changelog.com/terms, selfhosted.show, coder.show, podcastindex.org).
- No app code or tests modified yet (planning phase only).

## Next phase pointer
Plan is complete and decision-clean. When approved, begin **P1** on branch `audio-focus/01-recs-music-removal` per `04-verification-rollout.md`; P5 implements the verdict in doc 05. Do not start destructive code changes until approved.
