# App Store Submission Checklist — Parso Radio

## App Identity

| Field | Value |
|---|---|
| App name | Parso Radio |
| Bundle ID | `guru.parso.ios-radio-app` |
| Team ID | `3264Y8YUGV` |
| Version | 1.0.0 (build 1) |
| Platform | iOS 17.0+ |
| Device family | iPhone only (`TARGETED_DEVICE_FAMILY = 1`) |
| Primary category | Music |
| Secondary category | Entertainment |
| Content rating | 4+ (no objectionable content) |

---

## Assets Status

### App Icon
| Asset | Status | Location |
|---|---|---|
| 1024×1024 PNG (App Store icon) | **✓ EXISTS** | `ParsoRadio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` |

The icon is 1024×1024, 8-bit RGB (no alpha), non-interlaced — correct format.
The asset catalog (`Contents.json`) declares it as `"platform": "ios"` with `"size": "1024x1024"` — correct.

### Screenshots — **ALL MISSING, MUST GENERATE**

App Store Connect requires at minimum **3 screenshots** for **iPhone 6.7"**.
Since this is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), iPad screenshots are not required.

| Size | Device | Resolution | Required? | Status |
|---|---|---|---|---|
| 6.7" | iPhone 16 Pro Max / 15 Pro Max | 1290×2796 px | **YES** (min 3) | **MISSING** |
| 6.5" | iPhone 11 Pro Max / 12 Pro Max | 1242×2688 or 1284×2778 px | Covered by 6.7" | — |
| 5.5" | iPhone 8 Plus | 1242×2208 px | Optional | **MISSING** |

**How to generate screenshots:**
1. Run the app in Xcode Simulator on `iPhone 16 Pro Max` (iOS 17+)
2. Navigate to each screen and press `Cmd+S` (or Device → Screenshot)
3. Alternatively use `xcrun simctl io booted screenshot screenshot.png`

**Recommended screenshots to capture (3–5):**
1. iPod click wheel on a playing channel (show the now-playing card with track info)
2. Channel Selector sheet open (Favorites + Recently Played sections visible)
3. Track Detail popup (showing license badge, source, audio controls)
4. Terms of Service / EULA screen (required for App Store review compliance)
5. About / Privacy Policy screen

**Reference mockup:** `visual-mockup.png` (root of repo) shows the intended visual style.

### Code Signing — ✓ EXISTS
| Asset | Status | Location |
|---|---|---|
| Distribution certificate (.p12) | **✓ EXISTS** | `../apple-certs/ios_distribution.p12` |
| Distribution certificate (.cer) | **✓ EXISTS** | `../apple-certs/distribution.cer` |
| Distribution certificate (.pem) | **✓ EXISTS** | `../apple-certs/distribution.pem` |
| CSR | **✓ EXISTS** | `../apple-certs/ios_distribution.csr` |
| App Store provisioning profile | **✓ EXISTS** | `Parso_Radio_App_Store.mobileprovision` (root of repo) |
| P12 password | **✓ EXISTS** | `../apple-certs/p12_password.txt` |

These are also stored as GitHub Secrets (`CI_CERT`, `CI_CERT_PASSWORD`, `CI_PROFILE`, `CI_TEAM`) and used by the CI pipeline.

### Privacy Manifest — ✓ EXISTS
`ParsoRadio/Resources/PrivacyInfo.xcprivacy` declares:
- `NSPrivacyTracking: false`
- No collected data types
- UserDefaults API access for `CA92.1` (storing app settings)

---

## App Store Connect Metadata

Fill these in at [App Store Connect → My Apps → Parso Radio → App Information / Version](https://appstoreconnect.apple.com).

### App Information (one-time, not per-version)

**App Name:** Parso Radio *(30 chars max)*

**Subtitle:** Free Classical, Jazz & Audiobooks *(30 chars max — customize as desired)*

**Privacy Policy URL:** `https://parso.guru/privacy` ✓ (live, returns 200)

**Support URL:** `https://parso.guru`

### Version Information (per-version, 1.0.0)

**Description** *(4000 chars max):*
```
Parso Radio is an iPod-inspired internet radio player for classical music, jazz, audiobooks, and philosophy lectures — all completely free.

WHAT YOU GET
• 84 curated channels spanning Classical, LibriVox Audiobooks, FMA (Free Music Archive), and Oxford Lectures
• All content is 100% public domain or Creative Commons licensed — no ads, no subscriptions
• iPod-style click wheel interface: tap MENU to pick a channel, tap the wheel to play/pause, skip, or go back
• Offline-friendly: last channel and position restored automatically after restart
• Spoken-word channels (audiobooks, lectures) resume exactly where you left off
• No account, no sign-in, no tracking — ever

CHANNEL HIGHLIGHTS
Classical: Baroque, Romantic, Early Music, Symphony & Orchestra, Piano Classics, Chamber Music, Opera, and 20+ composers (Bach, Mozart, Beethoven, Chopin, and more)
LibriVox: Science Fiction, Mystery, Romance, Historical Fiction, Philosophy, Poetry, and 16 more genres
Oxford Lectures: Philosophy, Physics, Mathematics, History, and more from Oxford University podcasts
FMA: Jazz, Blues, Ambient, Folk, Instrumental, World Music, and more

PRIVACY
Parso Radio collects no personal data whatsoever. Playback position is stored on-device only. No analytics, no tracking, no account required.

LICENSES
All streamed music is public domain or licensed under Creative Commons (CC0, CC BY, or Public Domain Mark). Source and license are shown for every track.
```

**Keywords** *(100 chars max, comma-separated):*
```
classical,radio,music,free,audiobooks,jazz,librivox,public domain,lectures,iPod,offline
```

**What's New in This Version:**
```
First release of Parso Radio.
```

**Age Rating:** 4+ (complete the questionnaire; no objectionable content)

**Pricing:** Free

---

## Pre-Submission Checklist

### Build
- [ ] CI pipeline green (check GitHub Actions)
- [ ] Archive built with Release config via CI (`xcodebuild archive`)
- [ ] IPA exported with `ExportOptions.plist` (method: app-store-connect)
- [ ] Build uploaded to App Store Connect via `altool` or `xcrun altool` in CI

### Required Before Submission
- [ ] **Screenshots** — at minimum 3×iPhone 6.7" (1290×2796)
- [x] **Privacy policy URL** — https://parso.guru/privacy ✓ (live, returns 200)
- [ ] **Support URL** — parso.guru or similar
- [ ] App description filled in App Store Connect
- [ ] Keywords filled in
- [ ] Age rating questionnaire completed
- [ ] Pricing set to Free
- [ ] Primary category: Music

### App Review Notes (optional but recommended)
> Parso Radio streams audio from archive.org and freemusicarchive.org. Network access is required to load tracks. The app may show a loading spinner for a few seconds on first launch while tracks are fetched. A valid audio stream is available on any network connection.

### Common Rejection Reasons to Pre-empt
| Risk | Status |
|---|---|
| Missing privacy policy URL | **✓ RESOLVED** — https://parso.guru/privacy (live) |
| EULA/ToS gate not shown | **FIXED** — onChange moved to persistent ZStack (commit 713f78a) |
| Encryption (ITSAppUsesNonExemptEncryption) | **Declared false** in project.yml — correct for HTTP streaming |
| Background audio entitlement | **✓** — `UIBackgroundModes: [audio]` declared |
| No local storage of PII | **✓** — PrivacyInfo.xcprivacy confirms no personal data |

---

## GitHub Actions CI Pipeline

The existing workflow (`.github/workflows/`) handles:
1. Build & unit tests on every push to `main`
2. Archive + export IPA (Release config)
3. Upload to TestFlight via `altool`

Required GitHub Secrets (set in repo Settings → Secrets):
| Secret | Purpose |
|---|---|
| `CI_CERT` | Base64-encoded distribution.p12 |
| `CI_CERT_PASSWORD` | P12 password (from `p12_password.txt`) |
| `CI_PROFILE` | Base64-encoded .mobileprovision |
| `CI_TEAM` | Team ID `3264Y8YUGV` |

---

## Outstanding: No App Store Connect Record Yet?

If you haven't created the app record in App Store Connect:
1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. My Apps → **+** → New App
3. Platform: iOS, Name: Parso Radio, Bundle ID: `guru.parso.ios-radio-app`
4. SKU: `parso-radio-1` (or any unique string)
5. Fill in metadata as above, upload screenshots, then submit for review
