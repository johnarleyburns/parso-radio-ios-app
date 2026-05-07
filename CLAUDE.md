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
