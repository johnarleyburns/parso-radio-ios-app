# Current State

Status: implementing — Phase 5 (Agent Process Gates)

Decision status: all decisions settled in `decisions.md`.

## Phase Progress

| Phase | Branch | Status |
|---|---|---|
| 0 Contract Prep | `quality/regression-contract-tests` | merged |
| 1 Global MP3 | `fix/global-mp3-only-audio-policy` | merged |
| 2 Made For You | `fix/made-for-you-visibility-backfill` | merged |
| 3 Player Context | `fix/player-playback-context-surfaces` | merged |
| 4 Live Music | `fix/live-music-validation` | merged |
| 5 Process Gates | `chore/regression-quality-gates` | in_progress |

## Completed Anti-Regressions

- Made For You: `if showSection` gate removed; shelf always mounts with state machine (idle/loading/loaded/empty/failed)
- Made For You upgraders: one-time taste-profile backfill from `track_play_history` JOIN `tracks`
- Global MP3: all IA audio paths use `MP3AudioFormatSelector`; Ogg/FLAC/M4A/AAC/Opus/WAV/SHN rejected
- Playback context: `PlaybackContext` with origin/mediaKind set in all entry points; `activeMediaKind` routes surfaces
- NowPlayingSheet: uses `activeMediaKind` not `currentChannel?.mediaKind ?? .music`
- Live Music: `LiveMusicCandidateValidator` checks MP3-only, date match, display name; removed `pool.first` fallback
- Source guards: 6 tests document anti-patterns; 5 now passing, 1 to pass in Phase 5

## Verification

- `xcodegen generate` + `xcodebuild test -only-testing:ParsoMusicTests` passes all except `testAGENTSContainsRegressionContract` (this phase)
- All existing tests pass; no regressions introduced
