# Testing

## Constraint: no local toolchain

There is **no Swift/iOS compiler on the dev machine**. You cannot run the
test suites locally — they run on GitHub Actions (macOS) on every push to
`main` (~15 min/cycle). Mistakes are expensive, so the pre-push checks below
are mandatory.

## Mandatory pre-push checks

1. **`swiftc -parse <file>`** every changed Swift file. Linux can't resolve
   modules, so ignore `No such module`, `Cannot find type`, `Unknown
   attribute 'Published'`, `FoundationNetworking` — those are expected false
   alarms. Only genuine syntax errors (`expected`, unbalanced braces,
   `consecutive statements`, …) matter.
2. **curl-verify every IA query** before committing. A bad query that reaches
   CI costs 15 min; the same failure via curl costs seconds. Pattern:
   ```
   curl -s "https://archive.org/advancedsearch.php?q=ENCODED&fl[]=identifier&output=json&rows=5" \
     | python3 -c "import json,sys;r=json.load(sys.stdin);print(r['response']['numFound'])"
   ```
   If there's no `response` key the query errored (often `UNSUPPORTED_VALUE`
   — IA caps `q` at ~1700 chars; keep registry queries under it). Confirm a
   healthy, on-topic, content-safe pool (kids channels are 4+).
3. **Validate** `ia_queries.json` (JSON) and `project.yml` / workflows (YAML).
4. Read changed files back; never field-scope IA queries as `title:(a b)`
   (that ANDs words within one field); no leading `*wildcards*`.

## Test targets

- **`ParsoRadio/Core/Tests/` → `ParsoMusicTests`** — fast, offline unit tests
  (in-memory SQLite, `MockURLProtocol`). Channel taxonomy & counts, registry
  stamping/isolation, QueueManager decisions, DatabaseService, playlists &
  resume, search VM (history/classification/ranking), Track/URL logic,
  ambient sources, procedural-visualizer seed determinism, etc.
- **`ParsoRadio/Integration/Tests/` → `ParsoMusicIntegrationTests`** — hits
  **live** archive.org / FMA / Oxford. `testEveryRegistryChannelReturns
  HealthyStampedPool` is parametrized over EVERY registry channel and asserts
  a healthy stamped, isolated pool — adding a channel to `ia_queries.json`
  auto-covers it here.

## Integration-test convention

External services vary. **Skip (`XCTSkip`) on network/upstream emptiness; hard
-fail only on real filtering/code bugs** (0 results from a successful HTTP
call for an IA registry channel). `URLError` always skips. Oxford/News live
feeds skip-on-empty (verified-healthy units shouldn't redden CI on a server
blip).

## When you change things

- New/changed registry channel → curl-verify count + safety; the integration
  parametrized test covers it; update `ChannelTests` counts/id-set.
- New Swift symbol used by tests → make it `internal` (tests use
  `@testable import ParsoMusic`; `private` is not visible).
- New bundled resource → drop it under `ParsoRadio/`; XcodeGen bundles it
  (no project edits). For unit tests, `Bundle.main` is the host app.
- Behavior needing network/AVFoundation is validated by the integration
  suite, not unit tests.

## CI pipeline (`.github/workflows/ios.yml`)

`test` (unit) → `integration-tests` → `testflight-build` (archive, export,
upload). Build # = `github.run_number`; marketing version = `2.0.(run-103)`.
Workflows opt into Node 24 (`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24`). Watch a run:
`gh run watch <id> --exit-status`. All three jobs must be green before a build
reaches TestFlight.
