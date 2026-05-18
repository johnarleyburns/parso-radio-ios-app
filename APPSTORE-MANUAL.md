# Parso Radio — Remaining Manual App Store Tasks

Everything code/config-side from the review is now **done in the repo**
(v1.0.0, `fetch` background mode removed, iPad enabled, all-CC0 audio,
Mixkit video license confirmed by owner, Parso-Radio privacy page live).
The items below can only be done by you on a Mac + App Store Connect.

## 1. Screenshots (hard requirement — none exist)

Now that the app is **Universal (iPhone + iPad)** you must upload **both**:

- **iPhone 6.7"** — 1290 × 2796, **≥3 screenshots** (required)
- **iPad 12.9" / 13"** — 2048 × 2732 (portrait), **≥3 screenshots** (required
  because the app now supports iPad)

On a Mac:
```
# iPhone
xcrun simctl boot "iPhone 16 Pro Max"
xcrun simctl io booted screenshot iphone-1.png
# iPad
xcrun simctl boot "iPad Pro 13-inch (M4)"
xcrun simctl io booted screenshot ipad-1.png
```
Suggested shots: wheel on a playing channel; Main Menu / channel list; Search
with book/album results; Track Info sheet; an ambient channel with the
looping video backdrop.

> ⚠️ Verify the iPod UI looks acceptable on iPad before shipping. The layout
> is GeometryReader-driven and should scale, but it was designed for iPhone
> and has not been device-tested on iPad. If it looks stretched, tell me and
> I'll constrain the max width / center it for iPad.

## 2. App Store Connect record

If not created: My Apps → ➕ → iOS, name **Parso Radio**, bundle id
`guru.parso.ios-radio-app`, SKU `parso-radio-1`.

## 3. Version metadata (v1.0.0)

- **Subtitle (≤30):** `Free classical, jazz & audiobooks`
- **Keywords (≤100):** `classical,radio,music,free,audiobooks,jazz,librivox,public domain,lectures,ambient,kids`
- **Description:** channels overview (Classical / LibriVox audiobooks incl.
  **Children's Books** / Oxford lectures / FMA genres / ambient /
  **Children's Songs**); "no ads, no tracking; all public-domain or Creative
  Commons; source + license shown per track; offline-friendly; resume where
  you left off."
- **What's New:** `First release of Parso Radio.`
- **Primary / Secondary category:** Music / Entertainment
- **Promotional text / copyright:** © 2026 Parso Consulting

## 4. App Privacy & rating

- App Privacy label: **Data Not Collected** (matches manifest + policy). No ATT.
- Age rating questionnaire: all "None" → **4+**.

## 5. URLs

- **Privacy Policy URL:** `https://parso.guru/parso-radio-privacy`
  (new page pushed to the website this batch — confirm it loads; the host
  serves `*.html` extensionless, same as the existing `/privacy`).
- **Support URL:** `https://parso.guru`

## 6. Pricing

Free; all territories.

## 7. Submit

CI auto-archives + uploads to TestFlight on every green `main` push. On the
version page: select the build, paste the reviewer note below, **Submit for
Review**.

> Reviewer note: Parso Radio streams only public-domain / Creative Commons
> audio from archive.org, freemusicarchive.org and freesound.org; it hosts no
> content itself. Source + license are shown for every track. A copyright /
> DMCA reporting mechanism is in-app at **About → Copyright & DMCA**
> (info@parso.guru). Network access is required; a brief loading spinner may
> show on first launch. No account, no tracking, no data collection.

### Apple guideline coverage (IP / third-party content)

- **5.2 (Intellectual Property):** only PD/CC content; per-track source +
  license shown; in-app DMCA takedown path (About → Copyright & DMCA) with
  the §512(c)(3) notice elements + counter-notice.
- **1.2 (Safety / reporting):** users can report objectionable or infringing
  content by email from the About screen; we investigate and disable links
  to verified material.
- **1.5 (Developer info):** developer contact (info@parso.guru) is published
  in-app and in the listing.

## 8. One owner decision still open

- **Pre-vetted Children's Songs channel (optional follow-up).** The shipping
  `childrens-songs` channel is the safe IA **78rpm nursery-rhyme** records +
  curated `subject:"kids music"` tag (PBS/Nick Jr./Disney/indie comps). A
  netlabels candidate list for an additional hand-vetted channel is in
  `childrens-songs-candidates.csv` (clickable `stream_url`, `approved (Y/N)`
  column) — pending your manual approval pass; only `Y` rows get added.

## Done in code this batch (no action needed)

- `MARKETING_VERSION` → 1.0.0
- Removed unused `fetch` background mode + `BGTaskSchedulerPermittedIdentifiers`
- `TARGETED_DEVICE_FAMILY` → `1,2` (iPhone + iPad)
- Rain audio → CC0 (speakwithanimals/525046); all ambient audio now CC0;
  About → Credits + `ATTRIBUTION.md` updated
- Old Mixkit rain video restored; video license confirmed by owner
- Parso-Radio-specific privacy page added to the website + app link updated
- Added Children's Books (Audiobooks) and Children's Songs (Curated, safe
  LibriVox-anchored) channels
- Larger streaming buffer for poor connectivity
- Ambient channels keep play/pause; title tap opens menu; tapping a playlist
  auto-resumes
