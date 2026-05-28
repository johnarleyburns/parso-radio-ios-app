# Contribution Store — Setup Instructions (what YOU do)

_Exact steps to make the contribution feature work. The app code
(`ContributionStore` / `ContributionPromptEngine`) is dormant until these App
Store Connect (ASC) products exist with **matching IDs**. Do these in order._

> **The product IDs below MUST match the code exactly** (from
> `ContributionStore.swift`). Copy/paste them — a typo means the product silently
> won't load.

| Purpose | Product ID | Type | Price |
|---|---|---|---|
| Small tip | `guru.parso.tip.small` | Consumable | $1.99 |
| Supporter tip | `guru.parso.tip.medium` | Consumable | $4.99 |
| Patron tip | `guru.parso.tip.generous` | Consumable | $9.99 |
| Monthly support | `guru.parso.support.monthly` | Auto-renewable subscription | $2.99/mo |
| Yearly support | `guru.parso.support.yearly` | Auto-renewable subscription | $24.99/yr |

---

## STEP 1 — Agreements, Tax & Banking (do this FIRST; nothing sells without it)
1. ASC → **Business** → **Agreements, Tax, and Banking**.
2. Accept the **Paid Applications Agreement**.
3. Add a **bank account** (for payouts) and complete the **tax forms** (W-9 for US).
- Until the Paid Apps agreement is "Active," **no in-app purchase will work**,
  even in sandbox. This is the #1 reason IAPs "don't show up."

## STEP 2 — Create the 3 one-time tips (Consumables)
ASC → your app → **Monetization → In-App Purchases → (+)**. For EACH of the three:
1. Type: **Consumable**.
2. **Reference Name** (internal): e.g. "Small Tip".
3. **Product ID**: paste the exact ID from the table (e.g. `guru.parso.tip.small`).
4. **Price**: pick the tier matching the table ($1.99 / $4.99 / $9.99).
5. **Localization (English, U.S.)** — *Display Name* and *Description*, e.g.:
   - Small: "Buy us a coffee" / "A small thank-you that helps keep Parso free and ad-free. We give 10% of proceeds to the Internet Archive."
   - Medium: "Supporter" / "Support Parso's hosting and development — and unlock the supporter app icons. 10% of proceeds goes to the Internet Archive."
   - Generous: "Patron" / "A generous contribution to keep Parso free, ad-free, and independent. 10% of proceeds goes to the Internet Archive."
6. **Review screenshot**: a screenshot of the in-app Support screen (required —
   you can provide it once the Stage-2 UI ships).
7. Save.

## STEP 3 — Create the subscription group + 2 subscriptions
ASC → **Monetization → Subscriptions → Create Subscription Group**:
1. Group **Reference Name**: "Parso Support". Group **Display Name** (user-facing):
   "Parso Support".
2. Inside the group, **(+) Create** two auto-renewable subscriptions:
   - `guru.parso.support.monthly` — Duration **1 Month** — **$2.99**.
   - `guru.parso.support.yearly` — Duration **1 Year** — **$24.99**.
3. For each: **Display Name** + **Description** stressing **ongoing value**
   (required for auto-renew, Guideline 3.1.2(a)), e.g.:
   - "Parso Supporter (Monthly)" / "Keep Parso free and ad-free. Supporters get
     exclusive app icons, a supporter badge, and a direct line to shape the
     roadmap. 10% of proceeds goes to the Internet Archive. Renews monthly;
     cancel anytime in Settings."
4. **App Store Promotion / Review screenshot** for each (required).
5. In the subscription's settings, ensure the **Terms of Use (EULA)** and
   **Privacy Policy** URLs are present (App Information → these are app-level;
   subscriptions inherit them). Apple **requires** both for subscription apps.

## STEP 4 — Localized review notes (for the app reviewer)
When you submit the app version that includes these, add to **App Review
Information → Notes**:
> "Contributions are optional and support the free, ad-free app (hosting,
> copyright/DMCA handling, development). They are processed via In-App Purchase
> and unlock only cosmetic perks (app icons, a supporter badge). They are NOT
> charitable donations; separately, the developer voluntarily gives 10% of net
> proceeds to the Internet Archive. No functionality is gated behind payment."
- This pre-empts the two things a reviewer checks: (a) you're not collecting
  charity via IAP, and (b) you're not gating the app.

## STEP 5 — Submit the IAPs WITH an app version
First-time IAPs/subscriptions must be **submitted together with a new app
binary** (you can't approve them standalone the first time). So: attach all five
products to the next version you submit for review.

## STEP 6 — Test before submitting (Sandbox)
1. ASC → **Users and Access → Sandbox → Testers → (+)** — create a sandbox
   Apple ID (use a plus-alias email).
2. On your device: **Settings → (top) → … → Sandbox Account** (appears once a
   StoreKit-enabled build is installed) → sign in with the sandbox tester.
3. Run the TestFlight/dev build → open Support → buy a tip / subscribe. Sandbox
   subscriptions renew on an accelerated clock (e.g., 1 month ≈ 5 min) so you can
   verify renewal/cancel/restore quickly.
4. **Faster local option:** a `.storekit` configuration file in Xcode (File →
   New → StoreKit Configuration File) with the same product IDs lets you test in
   the simulator with no ASC round-trip. (I can generate this file for you.)

## STEP 7 — The Internet Archive remittance (operational, ongoing)
You committed to **10% of net proceeds** (what you receive after Apple's
15–30% cut). To honor + substantiate it:
1. Each payout period, compute 10% of your net contribution revenue.
2. Donate it at **archive.org/donate** (or set up a recurring donation).
3. **Keep records** (date, period, net revenue, 10% amount, donation receipt) —
   Apple or a user can ask you to back up the "10%" claim, and it keeps you
   honest.

## STEP 8 — Alternate app icons (the cosmetic perk) — needs ART
The code will wire `setAlternateIconName`, but you must supply the **icon image
sets** (1024² + the required sizes) for each supporter variant (e.g. "Gold",
"Classic Chrome"). Drop the PNGs in and I'll register them in the asset catalog +
`Info.plist` (`CFBundleAlternateIcons`). I can't produce real icon art.

---

## Quick checklist
- [ ] Paid Apps Agreement active; bank + tax done (STEP 1)
- [ ] 3 consumables created with exact IDs + prices + localized text (STEP 2)
- [ ] Subscription group + monthly + yearly created, ongoing-value text (STEP 3)
- [ ] Terms of Use (EULA) + Privacy Policy URLs set (STEP 3)
- [ ] Review notes added (STEP 4)
- [ ] Products attached to the submitted app version (STEP 5)
- [ ] Sandbox tester created + purchase flow tested (STEP 6)
- [ ] IA remittance process + record-keeping set up (STEP 7)
- [ ] Supporter icon art supplied (STEP 8)

## Where the code stands
- **Shipped (stage 1):** `ContributionStore` (StoreKit 2) + `ContributionPromptEngine`
  (tested). They activate automatically once the products above exist.
- **Next (stage 2, I build):** the toast, **Settings → Support** screen (with
  Restore + Manage Subscription + the required disclosures), track/session
  counters feeding the prompt engine, and the supporter badge on splash/About.
- **You provide:** the ASC products (this doc) + the supporter icon art.
