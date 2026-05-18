# App Store Submission Plan — Parso Radio

_Reviewed 2026-05-18. Source of truth for shipping v1._

## App identity

| Field | Value |
|---|---|
| App name | Parso Radio |
| Bundle ID | `guru.parso.ios-radio-app` |
| Team ID | `3264Y8YUGV` |
| Platform | iOS 17.0+, iPhone only (`TARGETED_DEVICE_FAMILY = 1`) |
| Primary / secondary category | Music / Entertainment |
| Age rating | 4+ |
| Price | Free |

## Status summary

Technically close to submittable. Build/sign/TestFlight pipeline is green;
privacy posture is clean. One licensing bug was found and **fixed in code**
(commit `e958daf`). Remaining work is mostly **manual App Store Connect tasks
on a Mac**; screenshots are the only true blocker.

## Resolved during review

- **Licensing (was a violation):** "Rainy Day" (Freesound svampen/334149) is
  **CC BY 3.0**, not CC0; code shipped it labelled CC0. Fixed: track license
  → `.ccBy`, added **About → Audio & Video Credits** (credits svampen + CC0
  sources + Mixkit note), corrected `Resources/Audio/ATTRIBUTION.md`, updated
  tests.

## Correct already (no action)

- App icon: 1024×1024, 8-bit **RGB, no alpha** (alpha → auto-reject) ✓
- `PrivacyInfo.xcprivacy`: `NSPrivacyTracking false`, no collected data,
  UserDefaults reason `CA92.1` declared ✓
- `ITSAppUsesNonExemptEncryption = false` (standard HTTPS only) ✓ — no
  encryption documentation needed
- App Transport Security: **no `http://` calls**; all sources HTTPS ✓
- Background audio: `UIBackgroundModes: [audio]` declared and used ✓
- Privacy policy `https://parso.guru/privacy` + support `https://parso.guru`
  both return 200 ✓
- EULA/Terms gate: `fullScreenCover` on `@AppStorage("tosAccepted")`, Apple
  third-party-beneficiary clauses present ✓

## Code changes to make before submitting

1. **Version number mismatch (do this).** `project.yml` ships
   `MARKETING_VERSION = 2.0.0` but this is the first release. Set
   `MARKETING_VERSION` to `1.0.0` (keep `CURRENT_PROJECT_VERSION = 1`). The
   ASC version string must equal the uploaded build's value.
2. **Unused background mode (recommended).** `UIBackgroundModes` also has
   `fetch` and `BGTaskSchedulerPermittedIdentifiers` is set, but nothing
   registers a `BGTask`. Remove `fetch` + the BG-task id (keep `audio`) to
   avoid review questions.
3. **iPad orientation key (optional).** iPhone-only build still has
   `UISupportedInterfaceOrientations~ipad` in Info.plist — dead config,
   harmless, optional cleanup.
4. **Mixkit video license (decision, not code).** Confirm the Mixkit Free
   License permits bundling the 3 ambient backdrop clips in a shipped app
   before release. (CC0/CC-BY audio is already handled.)

## Manual blockers (Mac + App Store Connect)

1. **Screenshots — required, none exist.** ≥3 at iPhone 6.7" (1290×2796).
   On `iPhone 16 Pro Max` sim (iOS 17+): wheel on a playing channel; main
   menu/channel list; search with book/album results; Track Info sheet; an
   ambient channel with looping video. `xcrun simctl io booted screenshot`.
2. **Create the ASC record** (if absent): iOS, "Parso Radio", bundle id
   `guru.parso.ios-radio-app`, SKU `parso-radio-1`.
3. **Version metadata:** paste description/subtitle(≤30)/keywords(≤100)/
   what's-new from "Listing copy" below; category Music / Entertainment.
4. **App Privacy label:** "Data Not Collected" (matches manifest + policy);
   no ATT.
5. **Age-rating questionnaire:** all "None" → 4+.
6. **Pricing/availability:** Free, all territories.
7. **URLs:** privacy `https://parso.guru/privacy`, support `https://parso.guru`.
8. **Upload build** (CI → TestFlight), select on version page, add reviewer
   note, **Submit for Review**.

## Reviewer note

> Parso Radio streams public-domain / Creative Commons audio from
> archive.org and freemusicarchive.org. Network access is required; a brief
> loading spinner may show on first launch while tracks are fetched. No
> account, no tracking, no data collection.

## Listing copy

**Subtitle (≤30):** `Free classical, jazz & audiobooks`

**Keywords (≤100):**
`classical,radio,music,free,audiobooks,jazz,librivox,public domain,lectures,ambient,offline`

**Description:** channels overview (Classical / LibriVox audiobooks / Oxford
lectures / FMA genres / ambient); emphasise "no ads, no subscriptions, no
tracking; all public-domain or Creative Commons; source + license shown for
every track; offline-friendly; resume where you left off". Update channel
counts if the children's channels (see investigation) are added.

**What's New (v1):** `First release of Parso Radio.`

## Pre-submission checklist

- [ ] `MARKETING_VERSION` → 1.0.0; `APPSTORE.md`/build consistent
- [ ] (rec) drop unused `fetch` background mode + BG-task id
- [ ] Mixkit license confirmed for app bundling
- [ ] CI green on the submitted commit (Unit + Integration + TestFlight)
- [ ] ≥3 × 6.7" screenshots uploaded
- [ ] ASC record created; metadata, keywords, what's-new filled
- [ ] App Privacy = Data Not Collected; age rating 4+; price Free
- [ ] Privacy/support URLs set; reviewer note added
- [ ] Build selected on version page → Submit for Review

## CI / signing (reference)

Workflow `.github/workflows/ios.yml`: build + unit tests + integration tests
+ archive/export/upload to TestFlight on every push to `main`. Secrets:
`CI_CERT` (b64 .p12), `CI_CERT_PASSWORD`, `CI_PROFILE` (b64 .mobileprovision),
`CI_TEAM` = `3264Y8YUGV`.

## Investigation: children's channels (2026-05-18, IA/FMA probed live)

- **Children's audiobooks (LibriVox via IA): strongly feasible.**
  `collection:librivoxaudio AND mediatype:audio AND (subject:"Juvenile
  fiction" OR subject:"Children's Fiction" OR subject:"Juvenile literature"
  OR subject:"Fairy tales")` → 130+ multi-chapter public-domain books
  (Oz, Peter Pan, Secret Garden, Grimm, Andersen). Clean & 4+-safe; fits the
  existing `lv-*` registry pattern.
- **Children's songs (IA): feasible with curation.** Best safe anchor:
  `collection:netlabels AND mediatype:audio AND (subject:"children's music"
  OR subject:children OR subject:kids OR subject:"nursery rhymes")` (~98
  curated CC netlabel kids tracks). Raw `subject:"Children's music"` (~494)
  is broader but less predictable for a 4+ channel.
- **Children's songs (FMA): NOT feasible.** Current FMA taxonomy has no
  children's/kids genre (only Blues/Classical/Country/Electronic/
  Experimental/Folk/Hip-Hop/Instrumental/International/Jazz/novelty/
  Old-Time/Pop/Rock/Soul-RB/Spoken).
- Recommended (pending go-ahead): add registry channels
  `lv-childrens-books` (Audiobooks) and `childrens-songs` (Curated,
  netlabels-anchored) to `ia_queries.json` with the existing
  pure-Lucene + `sort=random` + `matchTags=[id]` pattern, plus channel-count
  test updates.
