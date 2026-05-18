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

> Reviewer note: Parso Radio streams public-domain / Creative Commons audio
> from archive.org, freemusicarchive.org and freesound.org. Network access is
> required; a brief loading spinner may show on first launch while tracks are
> fetched. No account, no tracking, no data collection.

## 8. One owner decision still open

- **Pre-vetted Children's Songs channel (optional follow-up).** A safe
  LibriVox `childrens-songs` channel ships now. If you want produced kids
  *music* (not nursery-rhyme readings), say the word and I'll generate a
  netlabels candidate list (title / creator / license / link, by downloads)
  for you to personally approve/deny; approved IDs become a bundled
  pre-vetted channel.

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
