# Parso Radio — Claude Code Guidelines

## Build environment

This project runs on **Linux with no local Swift compiler**. There is no way to compile or type-check Swift locally. All builds go through GitHub Actions (macOS runners). A CI cycle takes ~15 minutes. Mistakes here are expensive.

## Rules before every push

### 1. Curl-test every API query before committing

Whenever you write or change any Internet Archive (or other HTTP API) query, run a curl against the live API and verify the response **before** committing. A failing query that reaches CI costs 15 minutes; the same failure found with curl costs 10 seconds.

Pattern for IA Solr queries:
```bash
curl -s "https://archive.org/advancedsearch.php?q=ENCODED_QUERY&fl[]=identifier&fl[]=title&output=json&rows=5" \
  | python3 -c "import json,sys; r=json.load(sys.stdin); print(r['response']['numFound'], [d.get('title') for d in r['response']['docs']])"
```

- If `numFound == 0`, diagnose before writing code or tests.
- The IA `musopen` collection has ~34 items only (Beethoven, Mozart, Brahms, Chopin, etc.). Bach, Vivaldi, and Rachmaninoff are **not** in it.
- IA Solr **disables leading wildcards by default** — never use `licenseurl:*publicdomain*` or similar in queries. All license filtering must happen in `LicenseValidator` in code.

### 2. Read every new file back line by line before staging

Syntax errors that a Swift compiler catches in milliseconds cost 10-minute CI cycles here. Read the full file after writing it; look for:
- Triple-quoted string literals that open and close on the same line
- `override var foo: T { value }` on a read-write superclass property (use `setUp()` assignment instead)
- Leading wildcards in Solr query strings

### 3. Match iOS API docs before using them

No local compiler means no type-checker. Before using any XCTest, AVFoundation, or SwiftUI API, verify the property/method signature. Key known gotcha: `XCTestCase.executionTimeAllowance` is a read-write `var` — set it in `setUp()`, never override it.

## Architecture

- **InternetArchiveService** — fetches from IA Solr; all license filtering in `LicenseValidator` (not in the query)
- **MusopenAPIService** — fetches from musopen.org/api (requires API key stored as `MUSOPEN_API_KEY` GitHub secret)
- **LicenseValidator** — `collection == "musopen"` → `.cc0`; leading-wildcard alternatives handled here
- **MetadataNormalizer** — confidence scoring; threshold 1.5 for composer channels, 0.0 for tag-only channels
- **DatabaseService** — async, `withCheckedContinuation`-wrapped SQLite operations
- **PlayerViewModel** — `@MainActor`; fetches IA + Musopen in parallel for composer channels
- **AudioPlayerService** — `@MainActor`; AVAudioSession set up in `init()`; `onTrackFinished` callback for auto-advance

## Hard-won lessons (read before touching playback or tests)

### `swiftc -parse` is NOT a type-checker
Local `swiftc -parse` only catches *syntax* errors. It does **not** catch: type
mismatches, wrong argument labels, `await`/`async` misuse, actor-isolation
errors, or `await` inside an `XCTAssert(...)` autoclosure (autoclosures don't
support concurrency). Those only surface on the macOS compiler in CI — a 15-min
round trip. Before pushing test changes especially: hoist every `await` out of
`XCTAssert*(...)` into a `let` first, and double-check argument labels/types by
re-reading the callee signature. Treat a green `-parse` as "not obviously broken
syntax," never as "compiles."

### Channel pool = the local DB, not the query
`QueueManager` builds a channel's playable pool from `db.fetchTracks(forChannel:)`
— i.e. every track ever **stamped** for that channel in SQLite. `saveTracks`
never deletes, so an old/broader query's results linger forever and repeat. Two
rules: (1) registry (iaQuery) channels carry a unique stamp, so on a successful
re-fetch we `pruneChannelTracks` to drop stamped tracks the *current* query no
longer returns (keeping downloads); (2) changing a channel's identity/curation is
safest via a **fresh channel id** (new stamp) + a migration map entry.

### A watchdog must cover the path it's meant to protect
The buffering-stall watchdog originally armed only when `autoPlay == true`, but
the launch-after-update hang happens on the `autoPlay == false` resume path — so
it never fired there. Lesson: when adding a safety timeout, enumerate *every*
code path that reaches the failure and make sure the guard covers them. The
watchdog now arms for every non-ambient load and keys off `readyGeneration`
(item reached `.readyToPlay`) vs `playbackConfirmedGeneration` (a real time
tick), so a paused-but-ready resume is never false-skipped while a never-ready
item is always skipped within `stallTimeout` (20 s).

### Resume / autoplay reliability
Resuming with `startAt > 0` DEFERS play until `.readyToPlay` (so the seek isn't
dropped — fixes "audiobook restarts at 0:00"). That deferral must be paired with
the play intent threaded all the way down (`PlayerViewModel.playTrack(autoPlay:)`
→ `AudioPlayerService.play(autoPlay:)`), NOT a `pause()` issued by `load()` after
the fact — the after-the-fact pause races the deferred play and leaves the track
silent with no duration. `onReady(duration)` publishes the runtime so the
progress bar appears even for a paused resume (IA search docs carry no runtime).
Launch resumes PLAYING (`autoPlay: true`) — it's a radio app.

### Curation philosophy: leave out rather than accidentally include
Prefer an explicit roster (named creators/ensembles) gated to a context
(`title:`/`subject:`) over a broad `subject:"…"` arm, which floods channels with
amateur uploads. Never add a creator without curl-checking: "John Williams"
pulled in the *film composer* (Star Wars). Validate every query with a random
`sort[]=random` sample and count distinct creators + scan for noise before
committing. Rather a small clean channel than a large one with bad tracks.
