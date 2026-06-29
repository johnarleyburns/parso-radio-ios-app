# 03 — Rights Audit, Licensing, Privacy & Copy

## Problem
Built-in podcasts are blanket-stamped `.publicDomain` regardless of their actual license, and public/in-app copy mentions music, FMA, albums, "auto-renewable subscriptions", and "10% of proceeds to the Internet Archive" — none of which will be accurate for a spoken-word-only release.

## Current Behavior
- `ParsoRadio/Core/Services/API/PodcastRSSService.swift:142` hardcodes `license: .publicDomain` for **every** podcast track; the RSS parser inspects no `<license>`/`<creativeCommons:license>` element; there is **no built-in vs user-added distinction**.
- `LicenseType` (`ParsoRadio/Core/Models/License.swift`): `publicDomain | cc0 | ccBy | rejected`. No "personal subscription / non-catalog" state.
- Oxford tracks hardcode `.ccBy` (`OxfordLecturesService.swift:131`); LibriVox via `LicenseValidator` (PD).
- `ParsoRadio.storekit`: 3 consumable tips, **zero subscriptions**; every description says "10% of proceeds to the Internet Archive".

## Research Signal (to be completed in P5)
Each built-in show's license must be checked against its official site/feed. "On a public RSS feed" ≠ "licensed for third-party in-app redistribution + presentation". Retain only shows with explicit reusable PD/CC terms.

---

## Podcast Rights Audit (P5) — framework + targets

> **FINALIZED 2026-06-28 → see `05-open-decisions-and-rights-audit.md` for the authoritative verdict.** All 32 built-ins were verified against primary sources. Outcome under the strict + conservative-PD-only bar: **KEEP 2** (`podcast-nasa-curious-universe`, `podcast-nasa-houston`, public domain); **REMOVE 30** (incl. 11 verified CC-NonCommercial shows dropped for tip-jar conservatism). The table below is the superseded *preliminary* read — kept only for history.

`Channel.defaults` has **32 built-in podcasts** (`Channel.swift:274–572`). For each retained show record: **show name · feed URL · license name · license URL · attribution text · date verified**. Remove any show that lacks an explicit reusable license.

> Preliminary risk read (SUPERSEDED by doc 05 — kept for history):

| Channel id | Show | Preliminary signal |
|---|---|---|
| `podcast-no-agenda`, `podcast-podcasting-2-0` | No Agenda, Podcasting 2.0 | Adam Curry feeds historically declare CC/no-agenda terms — **verify exact license** |
| `podcast-changelog`,`-go-time`,`-js-party`,`-practical-ai` | Changelog network | Changelog publishes some content under CC — **verify per show** |
| `podcast-security-now`,`-floss-weekly`,`-twit`,`-intelligent-machines`,`-tech-news-weekly`,`-macbreak-weekly`,`-windows-weekly`,`-untitled-linux-show`,`-hands-on-mac` | TWiT network | **No general reuse license assumed** — likely REMOVE unless a show states CC |
| `podcast-atp`,`-under-the-radar`,`-connected` | ATP / Relay FM | **No reuse license assumed** — likely REMOVE |
| `podcast-econtalk`,`-conversations-tyler` | Mercatus | **Verify** |
| `podcast-in-our-time` | BBC In Our Time | BBC content — **likely REMOVE** (no reuse license) |
| `podcast-philosophy-bites`,`-philosophize-this`,`-revolutions` | Independent | **Verify each** |
| `podcast-citations-needed`,`-linux-unplugged`,`-self-hosted`,`-coder-radio`,`-talk-python` | Independent/JB | **Verify each** |
| `podcast-nasa-curious-universe`,`-nasa-houston`,`news-democracy-now` | NASA / Democracy Now! | NASA = US-gov PD (strong); Democracy Now! is CC BY-NC-ND — **verify, attribute** |

### Outcome wiring (P5/P6)
- Add a verified built-in podcast license registry (e.g. extend `ia_queries.json`-style resource or a `podcast_licenses.json`) mapping channel id → {license, licenseURL, attribution, dateVerified}.
- `PodcastRSSService.toTrack` (:115–152) sets the verified built-in license from that registry instead of hardcoded `.publicDomain`.
- **User-added RSS** keeps a neutral/non-catalog state. Add `LicenseType.userSubscription` (additive) OR a `Track.isUserSubscription` flag so user feeds are *not* presented as part of Lorewave's curated PD/CC catalog. Copy: "personal subscription feature".

---

## Privacy / Terms / StoreKit / Docs Copy (P6)

### In-repo
- `lorewave-privacy.html` (root): remove "Free Music Archive" (:45), remove "auto-renewable subscriptions" (:49 — none exist), change "children's songs and stories" (:54) → stories.
- `ParsoRadio/Views/AboutView.swift`: "music and audiobooks" (:132), stale effective date (:204), IA-only source description (:220, add LibriVox/Oxford, drop FMA), :250.
- `ParsoRadio/Views/TermsView.swift:110`: remove "Free Music Archive (freemusicarchive.org)".
- `ParsoRadio.storekit`: rewrite all 3 product descriptions (:6–49) + settings (:51–60) — remove "10% of proceeds to the Internet Archive"; keep tip-jar-for-Lorewave language. (`ContributionStore.swift` product IDs unchanged.)
- `ParsoRadio/Views/SettingsView.swift:73`, `ContributionSupportView.swift:25`, `ContributionToast.swift:15`: remove "10%"/donation-to-IA copy.
- `ParsoRadio/Views/SplashView.swift:34`: "Free audio, forever." → **"Free listening, forever."**
- `ParsoRadio/Views/Listen/HomeSections.swift:46`: rewrite music-first welcome copy to spoken-word-first.
- `README.md` (:7,55,139–140), `AGENTS.md` (:9,85,195–227): drop FMA / music / Music-For-You / music-album regression items; restate sources as LibriVox + Oxford + verified podcasts + ambient.

### External (`../parsoguru`)
- `parsoguru/lorewave-privacy.html` (served at parso.guru/lorewave-privacy; identical to root): same edits as root. Cite: LibriVox → public domain; Oxford → CC BY / Open Education; each retained podcast → its exact license + source URL.
- `parsoguru/parso-radio-privacy.html` (older, FMA ref :69): update or confirm deprecated/unlinked.
- No terms web page exists in parsoguru (terms are in-app only).

---

## PrivacyInfo Manifest (P6, Step 8)

### Current
`ParsoRadio/Resources/PrivacyInfo.xcprivacy`: `NSPrivacyTracking=false`, no collected data, **only** `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1`).

### Required-reason API call sites (must be declared)
- **File timestamp** — `ArtworkService.swift:205–206` (`attributesOfItem` → `.modificationDate`), `LocalFileImportService.swift:70` (`.creationDateKey`).
- **Disk space / file size** — `CacheManager.swift:110,123,137` (`.fileSizeKey`), `OfflineDownloadService.swift:121` (`.fileSizeKey`).

### Deltas
- Add `NSPrivacyAccessedAPICategoryFileTimestamp` with caching reason `C617.1`.
- Add `NSPrivacyAccessedAPICategoryDiskSpace` with reason `E174.1` (or `85F4.1`) for cache management.
- Keep UserDefaults `CA92.1`.
- Do **not** add tracking or collected-data declarations — no telemetry/account/server collection is added, so the App Store label stays "no data collected".

## Data-Model Deltas
- Additive: optional built-in podcast license registry resource; `LicenseType.userSubscription` **or** `Track.isUserSubscription` (additive/defaulted).
- No destructive changes.

## Testing Strategy
- Unit: `PodcastRSSServiceTests` — built-in feed gets its registry license; user-added feed gets the neutral/non-catalog state, not `.publicDomain`.
- Unit/manifest: a test (or CI check) asserting `PrivacyInfo.xcprivacy` contains FileTimestamp + DiskSpace categories.
- Source-guard: no "Free Music Archive"/"10%"/"auto-renewable" in shipping copy (see `04-verification-rollout.md`).

## Open Questions
- **D-5:** Model the neutral user-feed state as a new `LicenseType.userSubscription` case vs a `Track` boolean flag. (Enum is more explicit; flag is less invasive.)
- **D-6:** For NASA/Democracy Now!, confirm exact attribution string + whether CC BY-NC-ND presentation (no edits) is satisfied by in-app streaming.
