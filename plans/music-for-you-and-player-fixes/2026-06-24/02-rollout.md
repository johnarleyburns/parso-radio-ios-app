# Rollout + verification

## Phased table (single phase)

| Phase | Branch | Depends on | Changes |
| --- | --- | --- | --- |
| 1 | `fix/music-for-you-and-player-surfaces` | main | A–E above, tests, AGENTS.md |

## Schema / migration safety

No schema changes. No DB migrations. All edits are view/controller/test/doc.

## Verification gate

```bash
xcodegen generate
xcodebuild test -project ParsoMusic.xcodeproj -scheme ParsoMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ParsoMusicTests
```

Must hold:
- `RegressionContractSourceTests` green, incl. new `testMusicControlsRendersScrubRow`.
- `MediaKindTests` / `PlayerPerKindControlsTests` green (behavior model unchanged).
- `MadeForYou*` / `RecommendationsControllerTests` green.

## Closeout

- Update `AGENTS.md` Regression Contract "Made For You" → "Music For You",
  music-only, header always mounts with spinner.
- Commit, merge to `main`, push, monitor `gh run list` until green; fix forward.
