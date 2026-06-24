# Decisions

## D1 — Harness style: Real loopback HTTP server + reroute
Boot an in-process `NWListener` HTTP/1.1 server preloaded with recorded fixtures; a
test-only `URLProtocol` reroutes outbound requests to `127.0.0.1:<port>`. A genuine
server that exercises real HTTP transport, while production URLs/assertions stay
unchanged. (Chosen over a sockets-free `URLProtocol` replay.)

## D2 — Recording: Record once, commit fixtures
A `record` mode (env flag `IA_HARNESS_MODE=record`) hits real APIs and writes
fixtures keyed by `host+path+sortedQuery`; commit them so replay is deterministic
and offline. Re-record on demand when upstream shapes change. (Chosen over
re-recording live each run.)

## D3 — Scope: All network-touching suites
InternetArchive, SpokenWord, Search, WholeBook, LiveMusicOnThisDay, BookForYou,
OxfordLectures move to the harness now. Taste and PlaylistPersistence are DB-only
and stay unchanged. (Chosen over IA-only.)

## Derived decisions (not user-facing forks)
- No production code changes: inject the harness `URLSession` into test-constructed
  services and replace raw `URLSession.shared` test calls. Base-URL injection is
  rejected because it would change produced `Track` URLs and break
  `contains("archive.org/...")` assertions.
- Fixtures loaded via `#filePath`-relative path (no resource bundling).
- Exact-signature match first; ordered pattern fallback for nondeterministic
  book-pick ids (`services/img/*`, `metadata/*`).
