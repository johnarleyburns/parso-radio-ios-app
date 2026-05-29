# Playback Reliability — Test Plan & Design Sequence

> Goal: make playback **bulletproof** around pause / resume / skip / back /
> channel-switch / background. The failures we keep hitting are catastrophic for
> a radio/audiobook app — one lost place in a book wrecks trust. This document is
> the design sequence and the **exact** tests we will build.

## Operating constraints (read first)

- **No local Swift compiler.** Everything verifies only on CI (~15 min/cycle).
  `swiftc -parse` catches *syntax* only — never types, argument labels,
  `await`/actor isolation, or protocol conformance.
- **ONE CI job. Fast tests only.** There is no nightly/heavy lane. Every test
  added here must run in the single PR job and finish fast. Practical rules:
  - **No real sleeps in tests.** Timeouts (stall, retry backoff, throttle) are
    made **injectable values** set to milliseconds in tests — NOT a `Clock`
    abstraction (too invasive for the constraint). A `Task.sleep(0.01s)` is
    "fast enough"; a 20 s stall timeout is not.
  - The fuzz harness uses a **fixed, bounded iteration count** chosen to run in
    a few seconds, with a deterministic seed set plus one random-seed run that
    prints its seed on failure.
  - All tests live in the existing `ParsoMusicTests` target — no new scheme.

## Player consolidation (DONE in this change)

The optional "Streaming Cache (Experimental)" toggle is **removed**.
`CachingResourceLoaderDelegate` is now the **single streaming path** for all
remote http(s) audio. The plain `AVPlayerItem(url:)` remains ONLY for
non-streamed sources: ambient **loops** (need `AVPlayerLooper`) and **local
files** (`file://`, where `cachingURL(for:)` returns nil and we fall through).

Why: two playback paths meant behavior differed by a hidden setting and doubled
the bug surface. One path = one thing to make correct and to test.

## Invariants (the contract — every test asserts a subset)

| # | Invariant | The bug it guards against |
|---|---|---|
| **I1** | **No silent dead state.** At quiescence: never `currentTrack != nil && !isPlaying && !isLoading && errorMessage == nil`. State is always exactly one of idle / loading / playing / paused-by-user / error. | rapid-back "track shown, no spinner, nothing plays"; search result never plays |
| **I2** | **Bounded loading.** Any load resolves to playing OR skipped OR error within `stallTimeout + retry budget`. Never loads forever. | infinite buffering; Music For You spinning |
| **I3** | **Savepoint truth & monotonicity.** The durable session offset never goes backward within a track and matches the last observed position (±tol) after pause / switch / background. | lost audiobook spot; throttle/pause races |
| **I4** | **Restore fidelity under lost writes.** After a "kill" that drops pending DB writes, restore lands on the durable track + offset. | jump-to-previous-resume-point |
| **I5** | **No cross-context leak.** A track resolved in context A never starts in context B. | Café Lento playing a playlist book; channel resuming a foreign track |
| **I6** | **Latest-action-wins.** Under interleaved actions exactly one engine is active, consistent with the last action; no stale watchdog skips a healthy track. | rapid-back; double `playTrack` |

Reentrancy note: everything is `@MainActor`, so these are **suspension-interleaving**
bugs (concurrent `playTrack` via `await` points), not multi-threading. The
harness must fire engine/service callbacks *while an action's `await` is parked*.

---

## Design sequence (ordered; each step is its own CI-green commit)

### Phase 0 — The seam (no behavior change; the gate for everything)

1. **`protocol AudioEngine` (`@MainActor`)** — extract the exact surface
   `PlayerViewModel` uses (verified: nothing else references `audioPlayer`):
   - reads: `isPlaying: Bool`, `duration: Double?`, `playbackRate: Float`
   - read/write: `repeatMode`, and callbacks `onReady`, `onTimeUpdate`,
     `onTrackFinished`, `onPreviousTrack`
   - methods: `play(url:track:looping:startAt:autoPlay:)`, `pause()`,
     `resume()`, `seek(to:)`, `skip()`, `setContentMode(_)`,
     `setPlaybackRate(_)`, `syncPlaybackState()`
   `AudioPlayerService` conforms unchanged. `PlayerViewModel.audioPlayer`
   becomes `any AudioEngine` (init param too). Production unchanged.

2. **Injectable timeouts** on `PlayerViewModel.init` with production defaults:
   `loadTimeout` (10), `stallTimeout` (20), and `RetryPolicy` (base 0.5).
   Tests pass tiny values (≈5–20 ms) so the watchdog/retry are fast but real.

3. **Injectable `UserDefaults`** for the `session.*` keys (mirror what
   `QueueManager` already does) so restore tests are isolated.

4. **`FaultyDatabase`** (test-only wrapper or a flag on the in-memory
   `DatabaseService`) that can **drop or delay the next N writes** — the only
   way to reproduce a background-kill lost write for I4.

> Phase 0 is the highest-risk refactor under "no local compiler." Land it ALONE,
> verify green, before any test below.

### Phase 1 — Test doubles + harness scaffold

5. **`FakeAudioEngine: AudioEngine`** — deterministic simulator. Per track, the
   test scripts: `readyAfter`, `firstTickAfter`, `tickInterval`, `duration`, and
   a mode ∈ { plays, `stallsForever`, `finishesAt(t)` }. It advances a virtual
   position and fires `onReady`/`onTimeUpdate`/`onTrackFinished` via short real
   delays (ms) so the orchestrator's own timers stay in proportion. Records every
   `play()`/`pause()`/`seek()` so tests assert "exactly one play() is live" (I6).
6. **Fake services** — `archiveService`/`podcastService` doubles whose
   `fetchTracks`/`resolveAudioURL` can be told to **succeed / throw / hang**
   (hang = the Music-For-You case). All are already injectable via
   `PlayerViewModel.init`.
7. **`PlaybackHarness`** helper: builds a `PlayerViewModel` wired to the fakes +
   in-memory `FaultyDatabase` + isolated defaults + ms timeouts; exposes
   `settle()` that yields the main actor until no scheduled fake event remains
   and no orchestrator op is in flight, then callers assert invariants.

### Phase 2 — Scripted regression tests (one per bug we shipped)

The fast, highest-value layer. Each reproduces a real bug and asserts the
relevant invariant. **Exact tests** (names final):

- `test_rapidBackSpawnsConcurrentLoads_onlyLatestPlays_noSilentState` — fire 6
  `goToPreviousTrack()` in a tight loop while loads are mid-resolve; after
  `settle()` assert exactly one track playing, `isLoading == false`, **I1 + I6**.
- `test_rapidSkip_neverStrandsLoadingSpinner` — same for `skip()`. I1, I6.
- `test_trackNeverReady_skippedWithinStallTimeout` — fake `stallsForever`; assert
  it advances to the next track within `stallTimeout`. **I2**.
- `test_allTracksStall_givesUpWithError_notInfinite` — every track stalls; assert
  it stops with an error after the give-up cap, never loops forever. I2.
- `test_recommendationFetchHangs_failsFast_notMinutes` — fake archive
  `fetchTracks` hangs; assert load resolves to error/empty within the bounded
  fetch timeout. I2.
- `test_switchChannelWhilePlaylistTrackResolving_noLeak` — start a playlist load,
  switch to a channel before it commits; assert the channel track plays, never
  the playlist track. **I5**.
- `test_channelDoesNotResumeForeignSavedTrack` — seed a channel position pointing
  at a non-stamped (playlist book) track; assert the channel starts fresh, clears
  the bad marker. I5.  *(plus a pure unit test for `resumeTrackBelongs`.)*
- `test_searchResultResolveFails_showsError_notSilent` — search result whose
  resolve throws; assert `errorMessage` set, not a silent spinner-less screen. I1.
- `test_musicAlbumPlaysRandomTrack_notAlwaysFirst` — album with known parts
  (pre-seeded in DB); over N advances assert >1 distinct part is chosen. *(unit
  on `randomAlbumTrack` for determinism with a seeded picker.)*
- `test_partLabelHiddenForMusic_shownForSpokenWord` — view-model-level flag check
  driving the label.

### Phase 3 — Durability / restore matrix (I3, I4)

- `test_pausePersistsExactOffset` — already exists; keep.
- `test_pauseThenKill_dropsDBWrite_restoreUsesDurableOffset_channel` — play to
  T=137, pause, `willResignActive`, **drop the DB write**, build a fresh VM on
  the same defaults + DB, `restoreLastSession`; assert resumes at 137 (the
  durable `session.position`), not the older DB value. **I4** — this is the
  exact bug just fixed.
- `…_playlist` — same on the playlist path.
- `test_allWritesDroppedDuringSession_restoreStillCorrect` — drop every DB write;
  restore must still land on the durable offset. I4.
- `test_savepointNeverGoesBackward` — drive ticks + a pause mid-track; assert the
  persisted offset is monotonic and equals the last tick. **I3**.
- `test_lockScreenPauseThenBackground_savesCurrentOffset` — pause via the engine
  (not `togglePlayPause`) then resign; assert durable offset is current. I3.

### Phase 4 — Bounded fuzz ("the simulated human")

One test, deterministic, fast:

- `test_fuzz_randomUserActions_holdAllInvariants` —
  - Seeded RNG; **fixed iteration budget** (start 2,000; tune to stay well under
    the CI window with ms timeouts).
  - Action space (weighted): play/pause, skip, back, seek±, switch-channel,
    switch-playlist, play-search-result, background, foreground, **relaunch**
    (new VM on same stores). Inter-action gaps drawn from {1–50 ms bursts (the
    rapid-tap regime), 100 ms–2 s human, idle}.
  - Fake engine injects random ready/stall/fail per load.
  - After each action: `settle()` then assert **I1, I2, I5, I6**; track the
    durable offset across relaunches for **I3, I4**.
  - On violation: dump seed + action log; add that seed to
    `test_fuzz_knownSeeds_replay` so a fixed bug stays fixed.

### Phase 5 — DEBUG runtime invariant checker (cheap insurance)

A `#if DEBUG` watchdog inside `PlayerViewModel` that `assertionFailure`s on I1/I2/I6
violations during real use, so manual TestFlight sessions surface what the fake
engine can't model about real `AVPlayer`.

---

## What stays UNtested (and the mitigation)

Real `AVPlayer`, the resource loader's networking, true buffering, interruptions,
route changes — the fake proves the **orchestrator brain**, not the real engine.
Mitigations: keep `AudioPlayerService`/`CachingResourceLoaderDelegate` thin (no
decisions); document the timing contract beside `protocol AudioEngine`; rely on
Phase 5 + a short manual on-device smoke list (skip-storm, background round-trip,
BBC redirect, a 30-min audiobook resume).

## Sequencing & risk

1. **Phase 0** (seam) — alone, green, first. Biggest risk under no-local-compiler.
2. **Phase 2** — the regression net; most protection per unit of effort.
3. **Phase 3** — durability matrix (audiobook place-loss is the worst failure).
4. **Phase 1 fuzz scaffold → Phase 4** — broad coverage.
5. **Phase 5** — runtime checker.

Risks: the seam is type-heavy and only CI verifies it; `settle()`/quiescence for
async actor code is the trickiest piece — prototype it on one scenario before
scaling the fuzz.
