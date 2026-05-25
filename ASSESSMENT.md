# Parso — Honest Assessment

_2026-05-25. A candid strategic read of the app: strengths, weaknesses,
competitive placement, and prioritized recommendations. Written from a full pass
over the codebase, git history, and content pipeline._

## Bottom line

Parso is a **well-engineered, legally-clean, feature-complete v1 sitting on top
of two structural problems it can't fully engineer its way out of: variable
content quality and streaming reliability.** It's genuinely good at what it is.
The open question isn't "is it shippable" (it is) — it's "who is this *for*, and
will it stay alive." The breadth and polish are ahead of the product focus and
the sustainability story.

## Strengths

1. **A defensible, rare niche.** Free, no account, no ads, no tracking, all
   PD/CC. Almost nobody ships this honestly. A real position, not a worse-Spotify.
2. **Legal posture is a genuine moat.** Per-track source + license, in-app DMCA,
   attribution discipline — far better than most indie content apps, and it
   directly de-risks App Review's 5.2 IP rejection (the thing that kills apps
   like this). A liability (UGC catalog) turned into a credibility asset.
3. **Surprising feature depth for v1.** Variable speed, sleep timer, bookmarks,
   chapters, offline, exact-resume, lock-screen ±15 s, full accessibility, iPad
   universal, history-driven recs. Most 1.0s ship a third of this.
4. **Distinct identity.** The click-wheel is memorable in a sea of identical
   players.
5. **Real engineering discipline under hard constraints** (no local compiler,
   15-min CI, curl-before-commit, hard-won-lessons doc). Coherent architecture
   (registry channels + stamp isolation + LicenseValidator separation).

## Weaknesses (ranked by threat)

1. **Streaming reliability is the #1 risk to ratings.** The git log shows ~6
   buffering fixes in the last ~25 commits. The stall cap converts the worst
   case to graceful failure, but the root fragility remains: streaming
   arbitrary-size/format third-party files (IA returns ~5% HTTP 500s, 40–48 MB
   single files) through AVPlayer. This is what earns 1-star reviews and it
   needs a reliability *strategy*, not more patches.
2. **Content quality has a ceiling you don't control.** The catalog is whatever
   is on IA/FMA — amateur uploads, mis-tags, "Baby Einstein for a Beethoven
   listener." Curated channels help but it's whack-a-mole, and the catalog
   structurally lacks the contemporary music most people want.
3. **No focus / heavy churn.** ~28 planning markdown files, several overlapping.
   Effort is going into re-litigating direction and breadth instead of nailing
   one core loop. Broad before deep.
4. **No sustainability model.** Free + no ads + no accounts = zero revenue, plus
   unfunded labor (curation, DMCA, support) and bandwidth goodwill. Fine for a
   hobby; a slow death for a product.
5. **Naming incoherence hurts discoverability.** "Parso Music" (device) vs
   "Parso Radio" (docs/listing) vs `ios-radio-app` (bundle). Both candidate
   names are generic and hard to rank/find.
6. **The click-wheel is double-edged.** Charming, but core gestures were
   undiscoverable enough to require an onboarding overlay. Non-standard
   navigation is a retention/accessibility risk.
7. **Discovery is weak** (improved with the two-arm rework, but still "more of
   the same"; no collaborative signal without accounts).

## Competitive placement

Not competing with Spotify/Apple Music (catalog + licensing — different game).
The real competitive set: **free classical-radio apps, LibriVox audiobook apps,
public-domain players, ambient/white-noise apps.**

- Honest framing: **Parso is the Swiss-Army-knife of free/public-domain audio.**
  Broader than any single competitor, but for any *one* job there's a more
  focused — often higher-quality or more reliable — alternative.
- Edge: **breadth + legal cleanliness + design identity + privacy.** That maps to
  a real, underserved audience: privacy-conscious, library/education-adjacent
  listeners who want free, ad-free, eyes-free long-form audio (audiobooks +
  lectures + classical).

## Recommendations (priority order)

1. **Pick a wedge and lead with it** — the free, ad-free **"public library /
   public radio"** identity (LibriVox + Oxford + PD classical + news). Strongest,
   most differentiated, most reliable-to-source story; leans into the legal moat.
   _(In progress: dropping the Contemporary/FMA arm to sharpen this.)_
2. **Make playback bulletproof before any new feature.** Reliability is table
   stakes and the shakiest area. Stall telemetry, pre-flight URL/derivative
   checks, bias toward known-good collections. _(In progress: new playback
   engine — see RECOMMENDATIONS-DESIGN / playback design.)_
3. **Curate down, not up.** A smaller set of reliably-excellent channels beats 77
   with amateur noise. Global quality gate, not per-channel firefighting.
4. **Settle the name** — one distinctive, searchable name signaling the niche.
5. **Decide the sustainability model now** (even "funded hobby" is a decision):
   tip jar / optional Pro (more downloads, sync) if accounts ever arrive.
6. **Then** ship CarPlay (started) → Siri/App Intents → Now-Playing widget.
7. **Get real users + light feedback** (LibriVox forums, r/classicalmusic,
   r/audiobooks, education/library communities). Curation is being tuned blind.

## The one decision that matters most

**Reliability + focus over breadth.** Capability isn't the risk; a broad,
charming app with intermittent buffering and amateur-flecked content getting
middling reviews and quietly stalling is. Narrow the promise to something
excellent and dependable, fix the playback fragility, and let the
legal/privacy story be the marketing.
