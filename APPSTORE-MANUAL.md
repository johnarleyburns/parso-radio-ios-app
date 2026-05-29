# Lorewave — Remaining Manual App Store Tasks

The app ships as **Lorewave** (`CFBundleDisplayName`). The Xcode target /
scheme / `.xcodeproj` are still internally named **ParsoMusic** (generated from
`project.yml` via XcodeGen) and the bundle id is unchanged
(`guru.parso.ios-radio-app`) — renaming those is **not** required and would
reset the App Store Connect record, so leave them. Marketing version is injected
by CI (currently the 2.0.x line; it can't drop below the existing 2.0.0
TestFlight builds). Universal (iPhone + iPad), iOS 17+.

Everything code/config-side is **done in the repo** (see "Done in code" at the
bottom). The items below can only be done by you on a Mac + App Store Connect.

## 1. Screenshots (hard requirement — none exist yet)

Universal app → upload **both** device sizes:

- **iPhone 6.7"** — 1290 × 2796, **≥3 screenshots** (required)
- **iPad 12.9" / 13"** — 2048 × 2732 (portrait), **≥3 screenshots** (required)

On a Mac:
```
# iPhone
xcrun simctl boot "iPhone 16 Pro Max"
xcrun simctl io booted screenshot iphone-1.png
# iPad
xcrun simctl boot "iPad Pro 13-inch (M4)"
xcrun simctl io booted screenshot ipad-1.png
```
Suggested shots (current UI): the click-wheel on a playing **Curated** classical
channel; the Main Menu showing **For You / Curated / Audiobooks / Lectures /
News / Ambient**; **Search** with the Both / Music / Audiobooks filter and
book/album results; the **Track Info** sheet on a multi-chapter book (chapters +
total time); an **Ambient** channel with the looping video backdrop.

> ⚠️ Verify the iPod UI looks acceptable on iPad before shipping. The layout is
> GeometryReader-driven and is capped to a phone-like width + centered on
> regular-width (iPad) — sanity-check it on a real iPad screenshot.

## 2. App Store Connect record

If not created: My Apps → ➕ → iOS, name **Lorewave**, bundle id
`guru.parso.ios-radio-app`, SKU `lorewave-1`. (If the older "Parso Radio"/"Parso
Music" record already exists for this bundle id, just **rename the app to
Lorewave** in App Information — don't make a new record.)

## 3. Version metadata

- **Subtitle (≤30):** `Classical, audiobooks & lectures`
- **Keywords (≤100):**
  `classical,audiobooks,librivox,lectures,public domain,radio,news,ambient,jazz,free,offline,oxford`
- **Description** — lead with the wedge (a public-library / public-radio
  listening app), then the channel families:
  - **Curated** — hand-picked public-domain classical, guitar, chamber, piano,
    symphony, world & religious music (no amateur uploads).
  - **Audiobooks** — LibriVox public-domain books by genre (Fiction, Sci-Fi,
    Mystery, Poetry, Children's Books, Great Books, …), with whole-book
    playlists and chapter navigation.
  - **Lectures** — free Oxford University lecture series (Philosophy, History,
    Physics, Computer Science, Economics, Medicine, …).
  - **News** — public-radio newscasts incl. international (NPR Up First, PBS
    NewsHour, 1A, Democracy Now!, BBC Global News, DW Inside Europe, CBC As It
    Happens); always plays the newest episode.
  - **Ambient** — gapless looping soundscapes with optional video backdrops.
  - **For You** — "Music for You" / "Books for You" channels built from the
    curated/audiobook channels you actually listen to (no cross-internet
    fishing).
  - Closing line: "No ads, no tracking. Everything is public-domain or Creative
    Commons; source + license shown for every track. Search the Internet Archive
    (filter Music / Audiobooks / Both). Download for **offline** listening, vary
    speed, set a sleep timer, bookmark, and **resume exactly where you left
    off** — even after a restart."
- **What's New:** `New name (Lorewave!), Music/Books "For You" channels,
  searchable Music vs Audiobooks filter, offline playlist highlights, and a
  more reliable player.`
- **Primary / Secondary category:** Music / Education (Education fits the
  audiobooks + Oxford lectures better than Entertainment).
- **Promotional text / copyright:** © 2026 Parso Consulting

## 4. App Privacy & rating

- App Privacy label: **Data Not Collected** (no analytics, no tracking, no
  account; contribution counters live only on-device). No ATT.
- ⚠️ **In-App Purchases nuance:** purchases are processed by Apple/StoreKit; the
  app stores nothing about them server-side. "Data Not Collected" still holds —
  but confirm the questionnaire doesn't force a "Purchases" disclosure for your
  account. If it does, mark **Purchases → not linked to identity, app
  functionality**.
- Age rating questionnaire: all "None" → **4+**. (News channels are mainstream
  public-radio; no mature-content flags.)

## 5. In-App Purchases / "Support Lorewave" (NEW — required before the build can
reference them)

Lorewave includes an optional **Support Lorewave** flow (Settings → Support, and
an occasional bottom toast). It is **not** framed as a charity donation — it
funds ongoing development + the ad-free/no-tracking experience, and **10% of
proceeds go to the Internet Archive** (disclosed in-app). This satisfies
guideline **3.1.1 / 3.2.1**: digital "support" of an app is allowed via IAP, and
because it isn't a tax-deductible charitable donation it must **not** use the
external donation/Apple-Pay-charity path.

**Full step-by-step is in `CONTRIBUTIONS-SETUP.md`.** App-review essentials:
- Create the products in ASC (consumable "tips" + the auto-renewable
  subscription) with the exact product ids the app loads.
- Subscription metadata must state what the user gets (ongoing value: supports
  development, ad-free, a supporter badge / Product-Board feedback access) —
  guideline **3.1.2(a)** requires ongoing value for an auto-renewable sub.
- Attach the IAPs to the **same build** you submit, or review will reject the
  references.
- Keep all on-screen wording "Support", never "Donate".

## 6. URLs

- **Privacy Policy URL:** `https://parso.guru/parso-radio-privacy` — ⚠️ confirm
  it still loads, and update the page's app-name references to **Lorewave**. If
  you register a Lorewave domain, point these there.
- **Support URL:** `https://parso.guru`

## 7. Pricing

App is **Free**; all territories. (Revenue is the optional IAP support above.)

## 8. Submit

CI auto-archives + uploads to TestFlight on every green `main` push. On the
version page: select the build, attach the IAPs (§5), paste the reviewer note,
**Submit for Review**.

> Reviewer note: Lorewave streams only public-domain / Creative Commons audio
> from archive.org (incl. LibriVox audiobooks and Musopen classical),
> freesound.org (ambient), and public-radio podcast RSS feeds (NPR, PBS, BBC,
> DW, CBC) for the News channels; it hosts no content itself. Source + license
> are shown for every track. A copyright / DMCA reporting mechanism is in-app at
> **About → Copyright & DMCA** (info@parso.guru). The optional "Support
> Lorewave" purchase funds development + the ad-free experience (10% to the
> Internet Archive); it is not a charitable donation. Network access is required
> for streaming; downloaded playlists play offline. No account, no tracking, no
> data collection.

### Apple guideline coverage

- **5.2 (Intellectual Property):** only PD/CC content + public-radio feeds;
  per-track source + license shown; in-app DMCA takedown path (About → Copyright
  & DMCA) with the §512(c)(3) notice elements + counter-notice.
- **3.1.1 / 3.1.2(a) (Payments):** optional support via IAP only; the
  auto-renewable subscription states its ongoing value; framed as "Support," not
  a charitable "Donate."
- **1.2 (Safety / reporting):** users can report objectionable/infringing
  content by email from the About screen.
- **1.5 (Developer info):** developer contact (info@parso.guru) is published
  in-app and in the listing.

## Done in code (no action needed)

- **Renamed to Lorewave** (`CFBundleDisplayName`); target/bundle id unchanged.
- **Wedge pivot:** removed the Contemporary category and all Free Music Archive
  (FMA) channels — the catalog is now Curated classical, LibriVox Audiobooks,
  Oxford Lectures, public-radio News (incl. international), Ambient, and For You.
- **For You channels** ("Music for You" / "Books for You") built from the
  curated/audiobook channels the user actually plays.
- **Search filter:** Both (default) / Music / Audiobooks scope, curl-verified IA
  collection filters.
- **Offline:** downloaded-playlist highlight badges; immediate offline detection
  with a non-destructive "You're Offline" notice (no lost audiobook position).
- **Reliability overhaul:** mathematically-modeled stall/retry policy,
  contiguous streaming cache (experimental, default off), crash-safe resource
  loader, bounded recommendation/resolve fetches.
- **Contributions:** Support flow + IAP scaffolding (see `CONTRIBUTIONS-SETUP.md`),
  10%-to-Internet-Archive disclosure.
- **MIT licensed / open source:** `LICENSE` + About → open-source section.
- Universal (iPhone + iPad), `fetch` background mode removed, all ambient audio
  CC0, privacy page linked.
