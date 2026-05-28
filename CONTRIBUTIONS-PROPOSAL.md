# Contributions / Sustainability — Proposal (ASSESSMENT #5)

_2026-05-28. A voluntary, non-intrusive contribution flow to keep the app free
& ad-free (hosting, copyright/DMCA handling, development) with a portion given to
the Internet Archive. Design-first; nothing implemented yet._

## 0. Read this first — the Apple-compliance reality that shapes everything

Three facts decide the whole design:

1. **Parso is a for-profit developer, not a registered charity.** Apple does
   **not** allow collecting *charitable donations* through In-App Purchase, and
   flags the word **"Donate"** as misleading when the money goes to a for-profit
   (users assume charity / tax-deductible). → We must **not** call it "Donate,"
   and must frame it as **supporting the app**.
2. **Money that supports the app must go through In-App Purchase** (Guideline
   3.1.1). We **cannot** link out to PayPal/Stripe/Patreon for this (3.1.3
   anti-steering; the external-link entitlements don't apply to us).
3. **Charitable donations to a 501(c)(3)** (the Internet Archive *is* one) may be
   collected *outside* IAP (Safari/SMS/Apple Pay) — but that money goes to **IA,
   not to us**, so it can't fund our DMCA/hosting. That defeats the goal.

**Conclusion (the compliant model):** sell **IAP "Support" products** framed as
supporting Parso (keeping it free & ad-free), and state that **we, the developer,
give a portion of proceeds to the Internet Archive**. The IA giving is *our*
discretionary use of revenue — never framed as the user donating to IA through
the app. This is exactly how indie apps run "tip jars" (Apollo, Overcast,
Halide, Carrot, etc.). One wording rule: lead with **"Support Parso"**, make the
IA line secondary ("…and a portion supports the Internet Archive"), so no
reviewer can read it as soliciting charity via IAP.

## 1. Products (StoreKit 2 / In-App Purchase)

| Product | Type | Example price | Notes |
|---|---|---|---|
| One-time tip — Small | **Consumable** | $1.99 | Repeatable |
| One-time tip — Medium | **Consumable** | $4.99 | |
| One-time tip — Generous | **Consumable** | $9.99 | |
| Monthly support | **Auto-renewable subscription** | $1.99/mo | + a light cosmetic perk (below) |
| Yearly support (optional) | Auto-renewable subscription | $19.99/yr | Better value, better LTV |

**Why a cosmetic perk on the subscription:** Guideline 3.1.2(a) says
auto-renewable subs must deliver *ongoing value*; pure-"donation" subs get
rejected. Give supporters something tiny and cosmetic — a **"Supporter" badge**
in About + **alternate app icons** — which satisfies 3.1.2(a) without gating any
real functionality (the app stays 100% usable for free). One-time consumables
need no perk.

## 2. The contribution toast (the ask)

A small, dismissible bottom card — **never a full-screen interstitial**, never
over the transport controls, never mid-listen.

**Eligibility (the engine — pure, unit-testable):**
- **Never** on first launch / first session.
- Only after genuine engagement: **≥ 12 tracks played** AND **≥ 2 distinct
  sessions** (tunable).
- Appears at a natural break (returning to the menu / after a track finishes /
  on foreground), not during active listening.

**Cadence & stop conditions:**
- Show **at most once per session**, and after a dismissal, **snooze 7 days / 5
  launches** before re-showing.
- **"Don't ask again" → never again** (hard stop, honored permanently).
- If the user has tipped recently or has an active subscription → **don't show**
  (show a one-time "thank you" instead, then stop).

**Buttons (3) and copy:**
```
   Enjoying Parso?
   Parso is free and ad-free. A contribution helps keep it that way —
   and a portion supports the Internet Archive.

   [ Support Parso ]   ← primary → opens the Support sheet
   [ Maybe later ]     ← snooze
   [ Don't ask again ] ← permanent opt-out
```
Note the deliberate change from your draft: **"Support Parso," not "Donate
now"** (compliance + honesty). "Remind me later" → "Maybe later"; "Never ask me
again" → "Don't ask again" (same behavior, tighter copy).

## 3. Settings → "Support Parso" section

- **Status**: "You're a supporter — thank you ✓", showing active subscription +
  renewal date and/or one-time-tip history. Non-supporters see the pitch.
- **One-time**: the three consumable tiers.
- **Monthly / Yearly**: subscribe buttons; if already subscribed, a **"Manage
  Subscription"** button that opens Apple's manage-subscriptions sheet
  (StoreKit `AppStore.showManageSubscriptions(in:)`). You can't cancel a sub
  in-app — it must deep-link to Apple. This is the "add/remove recurring" path.
- **Restore Purchases** button — **required** by Apple for subscriptions/
  non-consumables.
- **Required subscription disclosures** beside the subscribe button (Guideline
  3.1.2): product title, duration, price-per-period, auto-renew terms, and links
  to **Terms of Use (EULA)** + **Privacy Policy**.
- Footer line: *"Parso is free and ad-free. Contributions cover hosting,
  copyright/DMCA handling, and development — and we give a portion of all
  proceeds to the Internet Archive."*

## 4. Apple guideline checklist

| Guideline | Requirement | How we comply |
|---|---|---|
| 3.1.1 | In-app support uses IAP | All contributions are IAP (no external payment links) |
| 3.1.2 | Subscription disclosures | Shown at point of sale + functional links |
| 3.1.2(a) | Auto-renew = ongoing value | Cosmetic supporter perk (badge + icons) + maintained free app |
| 3.2.1 / 3.2.2 | Charity via IAP not allowed for for-profit | We sell "support," not charity; IA giving is from *our* proceeds |
| Misrepresentation | No "Donate"/"tax-deductible" for for-profit | "Support Parso" wording; truthful IA claim |
| Restore | Restore button present | In the Support section |
| 3.2.2 | Don't gate functionality / no nagging | Toast is dismissible, honors opt-out, never blocks the app |
| Metadata | Claims must be substantiable | Actually remit the IA portion; keep records |

## 5. Precedent (established apps doing this)

- **Apollo (Reddit)** — "Tip Jar": consumable tiers + alternate app icons as the
  thank-you. The template we're following.
- **Overcast** — patronage/support and a subscription tier.
- **Halide / Carrot Weather / many indies** — support tiers / subs with cosmetic
  perks.
- **Wikipedia app** — links *out* to donate, because Wikimedia is a nonprofit
  (the charity exception). That's the model only if you wanted to send users to
  IA directly — which doesn't fund you, so we don't use it.

## 6. Will it actually move money? (honest read)

- Voluntary-contribution conversion is **low** — typically **0.5–2%** of active
  users tip, often less. This will *offset* hosting/DMCA for a modestly-used free
  app; it won't fund a business.
- **Levers that genuinely help, most of which this design already uses:**
  - Ask **after real engagement** (✓ the 12-track / 2-session gate) — converts
    far better than a cold first-run ask.
  - **One tap to pay** (StoreKit sheet), **low entry price** ($1.99).
  - The **Internet Archive tie-in is a real conversion booster for *this*
    audience** — library/public-domain-minded users are mission-aligned and give
    more when they see the money supports the commons they value. (It's also
    ethically right: you lean on IA's bandwidth.)
  - **Recurring > one-time** for lifetime value — keep the monthly prominent.
  - A visible **"X recordings preserved / kept free"** impact line can lift
    giving (optional, later).
- For meaningful revenue you'd eventually need scale or a genuine **Pro tier**
  (e.g., unlimited offline, sync) — out of scope for this contribution-only model.

## 7. Implementation outline (when approved)

- **ContributionStore** (StoreKit 2): load products, purchase, restore, observe
  `Transaction.updates`, expose `isSupporter` / `activeTier`.
- **ContributionPromptEngine** (pure, unit-tested): inputs = tracksPlayed,
  sessionCount, lastPromptDate, state ∈ {locked, eligible, snoozed, optedOut,
  contributed}; output = shouldShowToast. All the cadence/eligibility logic
  lives here so it's testable without StoreKit.
- **Toast view** + **Settings → Support** section.
- ASC: configure the IAP/subscription products, the "portion to IA" must be
  truthful in review notes, set up the subscription group.
- One operational task for you: a lightweight way to actually remit the IA
  portion (and keep records, in case Apple asks to substantiate the claim).

## 8. Open decisions for you → see §9 for researched recommendations.

---

## 9. Researched recommendations (answers to your 4 questions)

### 9.1 Prices — recommended

Comparable in-app "support"/tip pricing I drew on:
| Source | Pricing |
|---|---|
| Apollo (the canonical iOS tip jar) | $1.99 / $4.99 / $9.99 / $24.99 / $49.99 (consumables) |
| Wikipedia donate asks | ~$2.75 / $5 / $10 / $20 |
| "Buy Me a Coffee" culture | $3–$5 sweet spot |
| Patreon creator tiers | $3 / $5 / $10 per month |
| Public radio (NPR-style) | "$5–$8/month" membership framing — familiar to *this* audience |
| Pocket Casts Plus / Overcast | ~$0.99/mo or ~$9.99/yr |

**Recommendation:**
- **One-time (consumables): $1.99 / $4.99 / $9.99** — labels like
  "Coffee / Supporter / Patron." The $1.99 floor maximizes participation;
  $4.99 is the conversion anchor; $9.99 captures enthusiasts.
- **Recurring: $2.99/month and $24.99/year** (year ≈ $2.08/mo, ~30% off — the
  "annual is the deal" nudge). $2.99/mo matches the public-radio pledge mindset
  this audience has and stays sustainable after Apple's 15–30% cut. Lower-
  friction fallback if conversion is weak: **$1.99/mo + $19.99/yr.**
- All are valid Apple price points.

### 9.2 Subscription — YES, and the "Product Board" idea

Include the subscription (recurring is the only path to sustainable revenue).

On **"supporters get input into the roadmap / feature requests" as the ongoing
value**: it's a *legitimate* ongoing service and a strong emotional hook for this
engaged audience — Apple has approved subs offering community access / priority
support / early access. **But don't rely on it ALONE for Guideline 3.1.2(a)** — a
reviewer can deem "feature-request input" too intangible, and it's real ongoing
*operational* work for a solo dev (you must actually run and honor it). So:
- **Use it as a value-add, paired with concrete cosmetic perks** (which carry the
  3.1.2(a) burden reliably).
- **Keep the promise modest** — "we read and prioritize supporter feedback /
  supporters get a dedicated feedback channel," *not* "you control the roadmap"
  (don't over-promise). Implement lightly at first (a supporters' feedback
  form, or a tagged GitHub Discussions board), not a heavyweight portal.

**Where to show the "Supporter" badge:**
- **Alternate app icon — YES (headline perk).** You can't overlay a badge on the
  live icon, but iOS `setAlternateIconName` lets supporters pick an exclusive
  icon variant (gold accent / classic-iPod chrome). This *is* "a badge on the
  app icon," done the Apple-sanctioned way.
- **Splash screen — YES, subtly.** A small "Supporter ✓" mark on the launch
  splash (SplashView already exists) — tasteful recognition, not gaudy.
- **About screen — YES.** A "Supporter — thank you" badge.
- **NOT in the now-playing/player UI** — keep the player clean.

### 9.3 Internet Archive share — "a portion" now, **10%** when ready

- Launch with **"a portion"** (zero commitment/risk while volume is unknown).
- When ready, commit to a named **10%** — credible and meaningful for this
  audience, and sustainable: 90% still covers Apple's cut + hosting/DMCA/dev.
- **Word it precisely:** *"10% of our proceeds (what we receive after Apple's
  commission) supports the Internet Archive."* Don't promise a % of *gross* —
  you never receive Apple's 15–30%. Keep records; Apple can ask you to
  substantiate the claim.
- A named % converts better than "a portion" for trust-sensitive,
  mission-aligned users — worth graduating to it.

### 9.4 Cosmetic perk — alternate app icons (primary) + splash/About badge

- **Alternate app icons** are the recommended primary perk: proven (Apollo),
  high perceived value, trivial (`setAlternateIconName`), and they satisfy
  3.1.2(a) cleanly. Offer 1–3 supporter-exclusive designs.
- Plus the **Supporter badge** on splash + About.
- **Tier the perks so the subscription has distinct ongoing value:**
  - **One-time tip →** unlocks the *current* supporter icon set + badge
    (permanent thank-you).
  - **Subscription →** all the above **plus ongoing** extras: new/rotating icons
    over time, the roadmap-feedback channel, and the splash badge. That ongoing
    delivery is what justifies a *recurring* charge under 3.1.2(a).

### 9.5 Net recommendation to implement (if you green-light)
One-time $1.99/$4.99/$9.99 (consumables) + $2.99-mo/$24.99-yr subscription;
ongoing value = alternate icons (one-time & sub) + sub-only roadmap input +
rotating icons; "a portion → 10% of net proceeds" to the Internet Archive;
toast + Settings → Support per §2–§3.
