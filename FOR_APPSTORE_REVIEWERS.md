# For App Store Reviewers

_This document supplements our App Store submission. It explains key reviewer-facing aspects of Lorewave._

---

## 1. Contributions / In-App Purchases

Lorewave offers **optional contributions** to support the free, ad-free app. All are processed via In-App Purchase (StoreKit 2):

| Product ID | Type | Price |
|---|---|---|
| `guru.parso.tip.small` | Consumable | $1.99 |
| `guru.parso.tip.medium` | Consumable | $4.99 |
| `guru.parso.tip.generous` | Consumable | $9.99 |
| `guru.parso.support.monthly` | Auto-Renewable Subscription | $2.99/mo |
| `guru.parso.support.yearly` | Auto-Renewable Subscription | $24.99/yr |

**Compliance points:**
- **NOT charitable donations.** These are contributions supporting the developer (Parso Consulting) to cover hosting, copyright/DMCA handling, and ongoing development.
- **No functionality is gated.** The app is 100% functional for free. The subscription unlocks only cosmetic perks (alternate app icons, a supporter badge on the main screen and About view, and the ability to submit feature-request input).
- **Internet Archive sharing.** The developer voluntarily gives 10% of net proceeds (after Apple's commission) to the Internet Archive, a 501(c)(3) nonprofit. This is the developer's own discretionary use of revenue — never framed as users donating to IA through the app. Records are kept to substantiate this claim.
- **Subscription ongoing value (Guideline 3.1.2(a)):** Subscribers receive alternate app icons (Beethoven badge for monthly; Emperor badge for yearly), a supporter badge displayed on the main screen and About screen, and a dedicated feedback channel for roadmap input.
- **Restore Purchases button** is present on the Support screen.
- **Manage Subscription button** deep-links to Apple's native subscription management sheet (`AppStore.showManageSubscriptions(in:)`).
- **Required subscription disclosures** (duration, price, auto-renew terms) are displayed at the point of sale.
- **Terms of Use (EULA) and Privacy Policy URLs** are present in App Store Connect → App Information. The privacy policy is also viewable in-app (About → Privacy Policy).

---

## 2. Age Assurance

Lorewave uses Apple's native **Declared Age Range API** (introduced WWDC 2024, iOS 17+) to implement a privacy-preserving age gate at startup:

- **Age gate threshold: 13.**
- On first launch, the App queries Apple's `AgeRangeService` with `[13]`.
- **Bracket A — Under 13:** The App is automatically locked into Kids Mode. Only curated children's songs and stories (public domain) are accessible. Search, News, in-app purchases, and the main literature catalog are hidden.
- **Bracket B — 13 to 17:** Full access to the classic literature catalog. All analytics/tracking are automatically disabled to comply with state-level minor-protection laws (e.g., Texas SB 2420, California Age-Appropriate Design Code).
- **Bracket C — 18+:** Standard full-featured experience.
- **Fallback (Declined/Unavailable):** The App defaults to Kids Mode for safety. A button labeled "Adult/Teen Verification" is provided, protected by a math-puzzle parental gate, allowing upgrade to the full catalog.

**Why this approach:**
- No birthdate collected (privacy-preserving).
- Apple handles the age attestation (no self-declare "I am 18" loophole).
- Kids Mode content is exclusively public domain children's literature — zero user-generated content, zero social features, zero purchases.
- Complies with COPPA, GDPR-K, and state-level minor-protection laws.

**Xcode entitlement:** `com.apple.developer.declared-age-range` (enabled in Signing & Capabilities).

---

## 3. Content Curation

Lorewave provides two levels of content curation:

### Channel Curation (built-in)
The App ships with ~18 pre-configured channels (Classical Guitar, Symphony Orchestra, Chamber Music, Piano Hour, Religious Music, Tribal Works, Historical Voices, Children's Songs, Children's Books, Cafe Lento, Great Books, News, Oxford Lectures, etc.). Each channel's content is sourced via an Internet Archive search query (`ia_queries.json`) filtered for public-domain and CC0 results.

### Curator Mode (user-driven)
A voluntary PIN-protected mode where users can audition candidate tracks and approve or reject them for a custom curated channel. Approved tracks only appear for that user on their device (per-channel JSON files stored locally). Rejected tracks are permanently hidden from that user's curated channel. This is entirely user-driven curation — the developer does not control or moderate what users curate for themselves.

**Content rights:** All content indexed and streamed by Lorewave is exclusively:
- **Public domain** (published before 1929, or government works)
- **Creative Commons CC0** (no rights reserved)
- Hosted on **archive.org** (the Internet Archive) or similar open repositories

The App does not host, re-host, or redistribute any audio files. The App streams directly from the source repositories. Copyright/DMCA takedown procedures are documented in the About screen with a designated copyright agent (info@parso.guru).

---

## 4. Kids Mode

Kids Mode is a safety feature that restricts the App to age-appropriate content:

- **Content:** Only two channels are available: Children's Songs and Children's Books. Both source exclusively from public-domain materials on the Internet Archive.
- **Hidden features:** Search, News, Settings (except Kids Mode toggle), in-app purchases, sharing, favorites, and the Curator/contribution features are completely hidden.
- **PIN gate:** Kids Mode can only be exited by entering a parent-set 4-digit PIN. The PIN is verified against a locally-stored hash.
- **Persistence:** Kids Mode state persists across launches.
- **Automatic trigger:** The Declared Age Range API may automatically lock users under 13 into Kids Mode.

---

## 5. Summary Checklist for Reviewers

| Concern | How We Address It |
|---|---|
| IAP are not charity | Framed as "Support Lorewave"; IA giving is from developer's proceeds |
| No functionality gated | All features work without payment; cosmetic perks only for supporters |
| Subscription has ongoing value | Alternate icons + badge + roadmap-input channel |
| Restore button present | Yes, in Settings → Support |
| Auto-renew disclosures | Shown at point of sale |
| EULA + Privacy URLs set | Yes, in ASC → App Information |
| Age-appropriate content | Declared Age Range API + Kids Mode + public-domain-only catalog |
| No UGC/social features | The App has no user accounts, messaging, or user-generated content |
| Content rights are clean | Exclusively public domain + CC0; DMCA agent designated |
| Privacy-respecting | No analytics, no tracking, no third-party SDKs, no data collection |
| Anti-steering compliance | No external payment links; all support goes through IAP |
