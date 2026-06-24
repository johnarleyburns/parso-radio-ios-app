# Integration Test Harness Server (record-and-replay)

## Problem
`ParsoMusicIntegrationTests` hit live third-party APIs (archive.org, podcasts.ox.ac.uk).
This makes the pre-push hook (which runs unit **and** integration tests) flaky: a
network blip or a degraded simulator aborts a push even when the developer's own
unit tests pass. We want the integration suite to exercise the real production
code paths (URL building, HTTP transport, JSON/HTML/RSS decoding, Track mapping)
but against a deterministic, offline **emulating server** seeded from **real**
recorded responses.

## Current Behavior
- Services (`InternetArchiveService`, `LiveMusicOnThisDayService`, `BookForYouService`,
  `OxfordLecturesService`) all issue requests through an injectable
  `URLSession` (`init(session: URLSession = .app)`) via `session.data(from:)`.
- Integration tests construct services with the **default** session and also make
  a few **raw** `URLSession.shared.data(from:)` calls (cover/thumbnail images, metadata).
- All endpoint URLs are hardcoded absolute (`https://archive.org/...`,
  `https://podcasts.ox.ac.uk/...`). Tests assert on produced `Track.streamURL`
  strings (e.g. `contains("archive.org/download/")`), so **URLs must stay real**.

## Research Signal
- Standard iOS record/replay is a `URLProtocol` (VCR/cassette). User explicitly
  wants a real **server**, so we use a loopback `NWListener` HTTP/1.1 server and a
  thin `URLProtocol` that reroutes outbound requests to it — keeping real URLs.
- Loopback (127.0.0.1) is exempt from App Transport Security; no Info.plist change.
- `#filePath`-relative fixture loading is the reliable way to read committed
  fixtures from the simulator (host FS is reachable; works on CI checkouts).

## Design
```
 RECORD (one-time, IA_HARNESS_MODE=record, real network):
   test → service.session → IAHarnessURLProtocol(record)
        → real archive.org / podcasts.ox.ac.uk
        → save fixture (signature → body+meta) → return real response

 REPLAY (default, offline):
   test → service.session → IAHarnessURLProtocol(replay)
        → http://127.0.0.1:<port>/<path>?<query>  (real socket round-trip)
        → IAHarnessServer → IAFixtureStore lookup → recorded bytes
        → return as HTTPURLResponse whose .url is the ORIGINAL archive.org URL
```
- **Signature** = `host + path + "?" + sortedQuery` (GET only). Exact match first,
  then ordered **pattern** fallbacks for nondeterministic ids:
  `archive.org/services/img/*` → representative cover (>2KB),
  `archive.org/metadata/*` → representative metadata-with-files.
  Exact (e.g. `metadata/Laws_Plato`) always beats pattern.
- **Concurrency**: Oxford crawls in parallel (TaskGroup); the server accepts
  concurrent connections; record writes are guarded by a serial queue.

### Components (all test-target only, `ParsoRadio/Integration/Harness/`)
- `IAFixtureStore.swift` — signature, manifest load/save, exact+pattern lookup, body IO.
- `IAHarnessServer.swift` — NWListener HTTP/1.1 server serving from the store.
- `IAHarnessURLProtocol.swift` — record/replay reroute protocol (static config, sequential).
- `IntegrationHarness.swift` — orchestrator: reads mode/env, starts server, builds `URLSession`.
- `HarnessTestCase.swift` — XCTestCase base; boots/teardowns harness, exposes `session`.
- `../Fixtures/` — committed `manifest.json` + `<sha>.json`/`<sha>.bin` body files.

## Data-Model Deltas
None. No production code or schema changes. Pure test-target additions + test
refactors + `project.yml` wiring. (Honors "keep real URLs / no base-URL injection".)

## Implementation Steps
1. Build harness components.
2. `project.yml`: add `Integration/Harness` to the integration test target sources;
   exclude `**/Integration/**` from the app target. `xcodegen generate`.
3. Refactor the 7 network suites to inject `session` (replace default sessions and
   raw `URLSession.shared` calls with the harness session).
4. RECORD: run the integration suite once with the record flag against real APIs
   (satisfies "real call first"); commit `Fixtures/`.
5. REPLAY: run the integration suite offline; verify green and deterministic.

## Suites in scope
Convert: InternetArchive, SpokenWord, Search, WholeBook, LiveMusicOnThisDay,
BookForYou, OxfordLectures. Leave as-is (no network): Taste, PlaylistPersistence.

## Testing Strategy
- After record, disable Wi-Fi/network and run `ParsoMusicIntegrationTests` — must pass.
- Run twice to confirm determinism (no `pool.first`/hash drift surfacing as misses).
- `ParsoMusicTests` unaffected.

## Open Questions
- Commit Oxford HTML fixtures verbatim (can be large) vs trim to minimal series set?
  Default: commit what record captures.
- Keep a documented `make record` path in README for re-recording when upstream
  shapes change.
