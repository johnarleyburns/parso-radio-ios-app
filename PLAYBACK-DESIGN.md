# Bulletproof Playback Engine — Design

_2026-05-25. Recommendation #2 from ASSESSMENT.md (reliability). Design-first;
staged implementation. The goal: a playback path that degrades gracefully on an
unreliable network, never double-fetches, unifies streaming with caching/downloads,
and **never** hangs in "infinite buffering."_

## Why a redesign (not another patch)

Playback is the app's #1 reliability risk: ~6 buffering fixes in the last ~25
commits. Root causes, from reading the code:

1. **No source coalescing.** A track can have a finished download, an *in-flight*
   download (playlist prefetch), and a stream URL. The current code sometimes
   opens a network stream for an item already being downloaded → double bandwidth
   and the "garbage prefetch file" class of bugs.
2. **Resolve + buffer fragility.** IA item→file resolution (metadata GET, 10 s
   cap) plus AVPlayer streaming of arbitrary-size files (~5% HTTP 500, up to
   ~48 MB single files) stalls; recovery was bolted on as watchdogs.
3. **Stall logic accreted** as generation flags scattered in the view model.
4. **No retry/backoff, no error classification** — a permanent 404 was treated
   like a transient blip and vice-versa.
5. **Streaming and downloading are separate** — playing something never warms
   the offline cache, and vice-versa.

## Constraint that shapes the architecture

No local Swift/iOS toolchain; CI builds `main` only (~16 min). AVFoundation can't
be unit-tested here. **So split policy from mechanism:**

- **Policy** (this design's core): pure, deterministic, platform-independent
  Swift — error classification, retry/backoff, the stall state machine, source
  selection, throughput estimation, cache eviction. **100% unit-testable on CI.**
- **Mechanism**: a thin `ResilientAudioPlayer` shell that owns `AVPlayer` +
  `AVAssetResourceLoaderDelegate` + `URLSession` and asks the policy what to do.
  Kept as small and dumb as possible.

This is what makes "bulletproof" verifiable: the brain is tested; the shell is thin.

---

## 1. Source model — the "already downloading" problem

At play time a track `t` has up to three byte sources:

| Symbol | Source | Cost |
|---|---|---|
| `L` | local **complete** file (finished offline download / import) | free, instant |
| `D` | **in-flight** download (playlist prefetch actively fetching) | already paid |
| `S` | remote **stream** (resolve IA id → file URL, then range-GET) | network |

**Priority: `L > D > S`.** Invariant: **one fetch per track** ("single-flight").
We never open `S` for a track that `D` is already fetching — that's the double-
download bug. Concurrent requests for the same id join the one in-flight op.

The elegant unification: **streaming writes to the same cache file a download
would.** Via the resource loader, a range-GET stream populates
`cache/<id>` on disk; when complete, that file *is* the offline download. So:

- Playing a track warms the offline cache for free.
- A playlist "prefetch download" and a "stream" are the same operation with the
  same single-flight writer; whoever asks second joins the first.
- Seeking back / replaying serves from the disk cache — no re-download.

`SourceSelector.select(SourceInputs) -> PlaybackSource` is pure/tested.

---

## 2. Buffering as a feedback system

Model the player's forward buffer as a fluid queue holding `b(t)` **seconds of
audio** ahead of the playhead:

```
db/dt = r_in(t) − R · [playing]
```

- `R` = playback rate (1.0, 1.5, …). Drain only while playing.
- `r_in(t)` = throughput / bitrate = (bytes/s) / (bytes/s of audio) = seconds of
  audio fetched per wall-second.

**Throughput estimate** (EWMA over byte samples):
`r̂ₙ = α·sampleₙ + (1−α)·r̂ₙ₋₁`, `α≈0.3`. Used to (a) pick a derivative bitrate
`≤ safety·r̂` (`safety≈0.8`) so playback can keep up, and (b) compute prebuffer ETA.

**Start/stall thresholds with hysteresis** (avoid rebuffer oscillation):

- Start playing when `b ≥ B_start` (prebuffer). Choose `B_start ≥ R·t_resolve + margin`.
- Rebuffer (pause) when `b ≤ 0` (AVPlayer `isPlaybackBufferEmpty`).
- Resume after a rebuffer only when `b ≥ B_resume`, with `B_resume > B_start`
  (hysteresis gap prevents flapping).

Defaults: `B_start = 2 s`, `B_resume = 5 s`. These live in policy and are tuned,
not hard-coded in the shell.

**Stall vs slow.** A stream that is *slowly progressing* (`r_in > 0`) is NOT
stalled — only `b = 0` **and** no playhead progress for `τ_stall` counts. This is
the existing watchdog, now formalized (§4).

---

## 3. Error classification + retry/backoff

Every failure is classified **permanent** vs **transient** — the single biggest
reliability lever, and pure/testable:

| Class | Examples | Action |
|---|---|---|
| **permanent** | 404/410/415/451, other 4xx, undecodable, bad URL | **skip now**, no retry |
| **transient** | timeout, 408/425/429, 5xx, connection lost, stall | **retry w/ backoff** |

**Backoff** (exponential + jitter), attempt `k = 0,1,…`:

```
delay(k) = min(D_max, D_0 · 2^k) · (1 + U(−j, +j))
```

`D_0 = 0.5 s`, `D_max = 8 s`, `j = 0.25`. Jitter takes a `rand∈[0,1)` parameter so
tests are deterministic.

**Two nested caps** (this is the formal cure for "infinite buffering"):

1. `maxAttemptsPerItem = 4` — transient retries for **one** item before giving up
   on it and skipping to the next.
2. `maxConsecutiveSkips = 4` — items skipped with **zero audio in between** before
   the engine stops and surfaces "couldn't start playback." A genuine playback
   tick resets this streak to 0.

(2) is exactly the cap I shipped in the view-model hotfix — the redesign moves it
into the tested policy core so it can't silently regress.

---

## 4. Playback state machine (generation-based)

```
idle → resolving → prebuffering → playing ⇄ rebuffering
                        │             │
                        ▼             ▼
                     failed ──→ retrying ──(k<K)→ resolving
                        │
                        └──(permanent | k≥K)──→ skip → (next) 
   any state with consecutiveSkips≥M and no audio ──→ giveUp(error)
   playing → (item end) → ended → (next)
```

Each load gets a monotonically increasing **generation**. A watchdog/callback is
valid only if its generation is current (stale ones are no-ops). Health is proven
by an actual playback tick (`confirmedGeneration`); a paused-but-ready item is
healthy too (`readyGeneration`) so a paused resume is never false-skipped. This is
`StallModel` — pure, tested — and the view model delegates to it.

---

## 5. Caching + eviction

- **Resolved-URL cache**: `id → file URL` (IA URLs are stable; cache for the
  session, persist the single/multi verdict as today). Eliminates repeat metadata
  GETs.
- **Byte cache**: resource-loader writes ranges to `cache/<id>`; completed files
  double as offline downloads. LRU, capped at `C_max` (e.g. 2 GB).
- **Eviction** (`CacheEvictionPolicy`, pure/tested): evict least-recently-used
  first to get under `C_max`; **never evict a user-pinned offline download**. If
  pinned alone exceeds `C_max`, evict all unpinned (best effort).

---

## 6. Module map

Pure policy core (this stage — `PlaybackResilience.swift`, all unit-tested):

- `PlaybackFailure` + `PlaybackFailureClassifier` — permanent vs transient.
- `RetryPolicy` — backoff schedule + the two caps.
- `ThroughputEstimator` — EWMA + bitrate pick + prebuffer ETA.
- `StallModel` — the generation state machine (§4).
- `SourceSelector` — `L > D > S`, single-flight (§1).
- `CacheEvictionPolicy` — LRU + pinned (§5).

Mechanism shell (next stage — `ResilientAudioPlayer.swift`):

- Owns `AVPlayer`, `AVAssetResourceLoaderDelegate` (range-GET → disk cache →
  serve), `URLSession`. KVO on `status` / `isPlaybackLikelyToKeepUp` /
  `isPlaybackBufferEmpty` / `timeControlStatus` feeds the `StallModel`. Exposes
  the same callback surface `PlayerViewModel` already uses
  (`onReady`, `onTimeUpdate`, `onTrackFinished`) so the swap is mechanical.

---

## 7. Staged rollout (each stage CI-validated before the next)

1. **Policy core + tests** ← *this commit.* Standalone, unused, behavior-neutral.
   CI proves the brain.
2. **`ResilientAudioPlayer` shell** behind the existing `AudioPlayerService`
   protocol surface; resource-loader caching; wired to the policy core. Not yet
   the default.
3. **Surgical swap**: route `PlayerViewModel` through the new player behind a flag,
   delete the accreted watchdog/stall code once the new path is confirmed, make it
   the default, remove the old one.

Rationale: replacing the audio engine wholesale, untested-locally, in one shot is
how you brick playback. Staging keeps `main` shippable throughout.

## 8. Test plan (stage 1)

`PlaybackResilienceTests`: classifier truth table (status/URLError → class);
backoff monotonic + capped + jitter-bounded + deterministic given `rand`; the two
caps trip exactly at threshold and reset on confirmed playback; `StallModel`
verdicts for {stale, confirmed, ready-paused, autoplay-stall, give-up};
`SourceSelector` priority + single-flight; EWMA convergence + bitrate pick;
eviction frees to target, LRU order, never evicts pinned.
