# 05 — Open Decisions Resolved + Final Podcast Rights Audit

Resolves D-2, D-3, D-5, D-6 and the P5 per-show podcast license verification. Supersedes the *preliminary* audit framework in `03-rights-privacy.md` (which is now historical for the podcast verdicts).

**Verification bar (locked):** retain a built-in podcast only with a license that has **no NonCommercial restriction** — i.e. **public-domain, CC0, CC BY, CC BY-SA, CC BY-ND, or open-government (OGL v3.0 / CC BY)**. Anything with an **NC clause (CC BY-NC*) or NC-style Crown copyright** (e.g. "non-commercial reproduction only") is **excluded** to avoid any NC-vs-tip-jar argument. (The original 32-show audit predated the round-2 additions and was decided under the stricter "PD-only" reading; the round-2 additions below broaden to the non-NC bar above — NC stays excluded either way, so the 11 dropped CC-NC shows remain dropped.)

---

## P5 — Final Podcast Rights Audit

### Problem
`Channel.defaults` ships 32 built-in podcasts (`Channel.swift:274–572`); `PodcastRSSService.swift:142` blanket-stamps every podcast track `license: .publicDomain` regardless of the show's real license. We must retain only rights-verified built-ins and stop mislabeling licenses.

### Current Behavior
All 32 built-ins fetch via one `PodcastRSSService.fetchTracks` path; no per-show license; no built-in-vs-user distinction.

### Research Signal (primary sources, verified 2026-06-28)
- **TWiT** (`twit.tv/about/license`): all public streams/on-demand shows = **CC BY-NC-ND 4.0**, attribute to TWiT.tv.
- **LINUX Unplugged** (`linuxunplugged.com` footer): **CC BY-NC 4.0** (Jupiter Broadcasting).
- **Democracy Now!** (transcript footer): **CC BY-NC-ND 3.0 US**, attribute democracynow.org; "some incorporated works may be separately licensed."
- **NASA** (`nasa.gov/nasa-brand-center/images-and-media/`): audio is **public domain (US-gov work)**; acknowledge NASA; **insignia/logos are NOT public domain**.
- **Changelog network** (`changelog.com/terms`): audio materials "may not be distributed… or modified" — **all-rights-reserved** (the `/terms` CC applies only to the terms document).
- **Self-Hosted** ("© Jupiter Broadcasting"), **Coder Radio** ("© The Mad Botter INC"), **Conversations with Tyler**, **Podcasting 2.0** ("open" = the dev index, not the audio): **no content CC/PD**.
- No-Agenda / ATP / Relay FM / EconTalk / In Our Time / Talk Python / Citations Needed / Philosophy Bites / Philosophize This / Revolutions: **no explicit CC/PD**.

### Verdict — KEEP (2, public domain only)
| Channel id | Show | Lines | License | Attribution |
|---|---|---|---|---|
| `podcast-nasa-curious-universe` | NASA's Curious Universe | `Channel.swift:555–563` | Public Domain (US gov) | "Courtesy of NASA" |
| `podcast-nasa-houston` | Houston We Have a Podcast | `Channel.swift:564–572` | Public Domain (US gov) | "Courtesy of NASA" |

### Verdict — REMOVE (30)
Delete `Channel.swift:274–552` (all entries from `news-democracy-now` through `podcast-revolutions`), keeping only the two NASA channels (`555–572`). Also rewrite the curation-bar comment (`267–273`) to: *built-in podcasts are explicit public-domain only; CC and value-for-value shows are excluded; user-added RSS is a personal subscription feature*.

Dropped for NonCommercial conservatism (verified CC, but NC): `news-democracy-now` (BY-NC-ND 3.0 US), `podcast-security-now`, `podcast-floss-weekly`, `podcast-twit`, `podcast-intelligent-machines`, `podcast-tech-news-weekly`, `podcast-macbreak-weekly`, `podcast-windows-weekly`, `podcast-untitled-linux-show`, `podcast-hands-on-mac` (all BY-NC-ND 4.0), `podcast-linux-unplugged` (BY-NC 4.0).
Removed as all-rights-reserved / no license: `podcast-no-agenda`, `podcast-citations-needed`, `podcast-podcasting-2-0`, `podcast-changelog`, `podcast-go-time`, `podcast-js-party`, `podcast-practical-ai`, `podcast-talk-python`, `podcast-self-hosted`, `podcast-coder-radio`, `podcast-atp`, `podcast-under-the-radar`, `podcast-connected`, `podcast-econtalk`, `podcast-conversations-tyler`, `podcast-in-our-time`, `podcast-philosophy-bites`, `podcast-philosophize-this`, `podcast-revolutions`.

> The in-code summaries claiming licenses for several removed shows (e.g. Changelog "open-licensed feed", TWiT "CC BY-NC-ND") were either inaccurate (Changelog) or accurate-but-NC-and-thus-dropped (TWiT/LUP/DN). Do not trust in-code license comments; the registry (below) is authoritative.

### Verified additions (2026-06-28, round 2) — non-NC bar

The user supplied 11 candidate shows. Every supplied URL was an **Apple Podcasts / website / blog landing page, not an RSS feed**, so each ADD was resolved to a real `https` RSS feed and license-verified against a primary source.

**ADD (5):**
| Proposed id | Show | License (verified source) | RSS feed | Attribution |
|---|---|---|---|---|
| `podcast-nasa-small-steps` | NASA — Small Steps, Giant Leaps | Public Domain, US-gov (nasa.gov media guidelines) | `https://www.nasa.gov/feeds/podcasts/small-steps-giant-leaps` (listed on the show page) | "Courtesy of NASA" |
| `podcast-ipse-dixit` | Ipse Dixit | **CC0 / Public Domain** (`shows.acast.com/ipse-dixit`: "Copyright CC0/Public Domain") | `https://feeds.acast.com/public/shows/ipse-dixit` (listed on the Acast page) | none required (courtesy: Brian L. Frye) |
| `podcast-endless-knot` | The Endless Knot | **CC BY-SA 4.0** (`alliterative.net`, stated each episode) | `https://www.alliterative.net/podcast?format=rss` (older eps' `http://` podtrac feed is unusable) | "The Endless Knot — Aven McMaster & Mark Sundaram, CC BY-SA 4.0" |
| `podcast-rpa` | The Rural Payments Agency Podcast | **OGL v3.0** (ruralpayments.blog.gov.uk footer) | `https://feeds.buzzsprout.com/1902916.rss` (Buzzsprout id from the post; **verify**) | "Contains public sector information licensed under the Open Government Licence v3.0" |
| `podcast-inside-hmcts` | Inside HMCTS Podcast | **OGL v3.0** (insidehmcts.blog.gov.uk footer) | `https://feeds.buzzsprout.com/2259279.rss` (Buzzsprout id from the hub; **verify**) | "Contains public sector information licensed under the Open Government Licence v3.0" |

**EXCLUDE — verified fail:**
- **WB-40** — site is down ("pardon our dust"); no confirmable feed/license; historically CC BY-NC-SA (NC).
- **Canada CRA "Taxology"** — Crown copyright; canada.ca terms permit **non-commercial reproduction only** (commercial needs written permission) → NC-style, excluded per the tip-jar decision. (A feed does exist: `…/cra-arc/…/rss/txlgy-strmng-eng.xml`.)

**EXCLUDE — no usable feed** (re-verified 2026-06-28; dropped per "if the feed doesn't work, remove it"):
- **Code for Thought** — `codeforthought.xyz` returns a transport error (twice); no feed/license obtainable.
- **Open Source Creative** — `opensourcecreative.com` dead (transport error); Apple id dates to 2014; defunct.
- **Met Éireann — Weather Forecast** — met.ie exposes only an on-page audio player; no podcast RSS feed surfaced; copyright is not an explicit CC.
- **5 mins with the FMA (NZ)** — fma.govt.nz exposes only a JS player / search-listing; no per-show RSS feed surfaced; copyright is not an explicit CC.

These 4 are **dropped** (not added). Re-add only if a working `https` podcast RSS feed **and** a non-NC license are later supplied.

**Compliance caveats for the ADDs:**
- OGL v3.0 excludes departmental logos / the Royal Arms — do not reuse the UK gov crest; the Buzzsprout show art is fine.
- NASA insignia is not PD (as already noted for the other NASA shows).
- CC BY-SA / OGL require the attribution string above rendered on the now-playing / info surface; stream episodes **unmodified** (BY-SA's ShareAlike isn't triggered by verbatim streaming).
- **Feed verification is mandatory before shipping**: confirm each `https` feed parses real `<enclosure type="audio…">` items. The two Buzzsprout ids were inferred from the gov pages, and Squarespace `?format=rss` may return only recent items.

**Net built-in podcasts after round 2: 7** — the 2 original NASA PD shows (`podcast-nasa-curious-universe`, `podcast-nasa-houston`) + these 5 additions. (The 4 unverifiable candidates above were dropped — no working feed.)

### D-6 — Compliance rules (original kept shows; round-2 additions carry their own attribution, above)
- Acknowledge **"Courtesy of NASA"**; never imply NASA endorsement of Lorewave.
- **Review/replace the 2 NASA channel artwork images** (`imageURL` at `:562` and `:571`, megaphone.imgix) — if they embed the NASA insignia/"meatball"/"worm", swap for non-insignia art (logos are not PD).
- NASA audio occasionally embeds third-party copyrighted material (marked); low risk for these two shows.
- ND/NC compliance notes are now **moot** (no CC shows retained).

---

## D-2 — Lecture search scope → **browse-only**
- **Decision:** Search exposes **Audiobooks + Podcasts** only. Lectures stay browse-only.
- **Rationale:** Oxford lectures come from a `podcasts.ox.ac.uk` CMS crawl (`OxfordLecturesService`), not the IA search index — there is no backing query for a lecture search scope without new infrastructure.
- **Touches:** `SearchViewModel.SearchScope` (`SearchViewModel.swift:28–47`) keeps `audiobooks`, `podcasts`; default `.audiobooks` (`:50`).

## D-3 — "track" wording → **targeted, not total**
- **Rule:** replace "track" only where it denotes a chapter/episode/lecture; keep neutral generic phrasing elsewhere ("items", "Recently Played", "played").
- **Per-string map:**
  | File:line | Current | Action |
  |---|---|---|
  | `Views/SearchView.swift:31` | "Search music, audiobooks, podcasts..." | "Search audiobooks and podcasts…" |
  | `Views/SearchView.swift:175` | "Find music, audiobooks, and podcasts." | "Find audiobooks and podcasts." |
  | `Views/SearchView.swift:377–383` | "Track"/"Album"/"Book" capsules | "Book"/"Episode" only (album/track removed in P3) |
  | `Views/Library/LibraryView.swift:68` | "N tracks" | "N items" |
  | `Views/RecentlyPlayedScreen.swift:17` | "Tracks you play will show up here." | "Anything you play will show up here." |
  | `Views/Player/Controls/MusicControls.swift:14,22` | "Previous track"/"Next track" | removed with MusicControls (P4) |
  | `Views/FavoritesScreen.swift:43` | "…any track, book, podcast, or lecture…" | "…any book, podcast, or lecture…" |
  | `Views/SettingsView.swift` (generic "tracks") | various | keep where generic, else "items" |
- Section-header `Section("Tracks (N)")` in `ItemDetailView.swift:122` already switches Book→"Chapters" via `tracksNoun`; force book/series wording (P3).

## D-5 — User-feed license state → **boolean flag + built-in registry**
- **Decision:** add `Track.isUserSubscription: Bool = false` (additive/defaulted) and a new bundled `ParsoRadio/Resources/podcast_licenses.json` registry.
- **Registry shape** (all 7 confirmed built-ins; `license` is the coarse `LicenseType` bucket, with precise name/url/attribution alongside):
  ```json
  { "podcast-nasa-curious-universe": { "license": "publicDomain", "name": "Public Domain (US Government work)", "url": "https://www.nasa.gov/nasa-brand-center/images-and-media/", "attribution": "Courtesy of NASA" },
    "podcast-nasa-houston":          { "license": "publicDomain", "name": "Public Domain (US Government work)", "url": "https://www.nasa.gov/nasa-brand-center/images-and-media/", "attribution": "Courtesy of NASA" },
    "podcast-nasa-small-steps":      { "license": "publicDomain", "name": "Public Domain (US Government work)", "url": "https://www.nasa.gov/nasa-brand-center/images-and-media/", "attribution": "Courtesy of NASA" },
    "podcast-ipse-dixit":            { "license": "cc0",          "name": "CC0 1.0 / Public Domain", "url": "https://creativecommons.org/publicdomain/zero/1.0/", "attribution": "Ipse Dixit (Brian L. Frye)" },
    "podcast-endless-knot":          { "license": "ccBy",         "name": "CC BY-SA 4.0", "url": "https://creativecommons.org/licenses/by-sa/4.0/", "attribution": "The Endless Knot — Aven McMaster & Mark Sundaram" },
    "podcast-rpa":                   { "license": "ccBy",         "name": "Open Government Licence v3.0", "url": "https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/", "attribution": "Contains public sector information licensed under the Open Government Licence v3.0" },
    "podcast-inside-hmcts":          { "license": "ccBy",         "name": "Open Government Licence v3.0", "url": "https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/", "attribution": "Contains public sector information licensed under the Open Government Licence v3.0" } }
  ```
- **`PodcastRSSService.toTrack` (`:115–152`)**: stop hardcoding `.publicDomain` (`:142`). Instead:
  - built-in channel id in registry → use registry `license` + carry attribution metadata;
  - user-added feed → `isUserSubscription = true`, neutral non-catalog state; UI copy: "personal subscription feature", never presented as part of Lorewave's curated public-domain catalog.

## Data-Model Deltas (all additive)
- `Track.isUserSubscription: Bool = false` — additive/defaulted; legacy rows decode false.
- New bundled resource `podcast_licenses.json` — `xcodegen generate` after adding.
- No `LicenseType` change required — the additions reuse existing buckets (`publicDomain` for NASA, `cc0` for Ipse Dixit, `ccBy` for CC BY-SA + OGL); the precise license *name/url/attribution* live in the registry, not the enum.

## Implementation Steps (folds into Phase P5 of `04-verification-rollout.md`)
1. Edit `Channel.swift`: remove the 30 podcast entries (`274–552`), keep the 2 NASA channels, rewrite the curation-bar comment (`267–273`) to the non-NC bar.
2. Add the 5 round-2 podcast `Channel` entries (`podcast-nasa-small-steps`, `podcast-ipse-dixit`, `podcast-endless-knot`, `podcast-rpa`, `podcast-inside-hmcts`) — `category: "Podcasts"`, `contentType: .spokenWord`, `preferredSource: "podcast"`, `feedURL`, `tags: [id]`. **Verify each `https` feed parses real audio enclosures first.**
3. Add `Track.isUserSubscription`; add `podcast_licenses.json` with all 7 confirmed entries; rewrite `PodcastRSSService.toTrack` license logic; `xcodegen generate`.
4. Review/replace NASA artwork URLs if they embed NASA insignia; ensure OGL shows don't use the UK gov crest.
5. Update `ChannelTests` for the new built-in podcast set (the 7 confirmed ids) and remove assertions on deleted shows; also fix `MediaKindTests`, `IntentsTests`, `BackgroundIntentTests` (see review gaps).
6. D-2/D-3 copy + scope edits land in P3; D-3 player-string edits land with P4 removals.

## Testing Strategy
- `ChannelTests`: built-in podcasts == exactly the 7 confirmed ids (2 NASA + 5 round-2 additions); no removed id present.
- `PodcastRSSServiceTests`: registry returns the right license per show (NASA → `publicDomain`/"Courtesy of NASA"; Ipse Dixit → `cc0`; Endless Knot → `ccBy`/"CC BY-SA 4.0"; RPA & HMCTS → `ccBy`/OGL attribution); a synthetic user feed → `isUserSubscription == true` and not labeled catalog PD/CC.
- Source-guard: no removed podcast ids/feed hostnames remain in shipping `Channel.swift`; no NC-licensed feed host present.
- Search behavior: scopes == {audiobooks, podcasts}; default audiobooks.

## Open Questions
- **Q-A:** With only 2 built-in podcasts, should the "Podcasts" Explore chip/scope lead with a "Add your own feeds" affordance? (Product polish; default: yes, surface user-add prominently.)
- **Q-B:** Revisit the dropped CC-NC shows later if the tip jar is reframed/removed? (Tracked; not for this release.)
