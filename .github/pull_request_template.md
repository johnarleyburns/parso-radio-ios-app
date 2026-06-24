## Checklist

### Recurring Regression Gates

- [ ] Made For You visibility/backfill unaffected — section mounts unconditionally
- [ ] Live Music candidates validated before display (MP3-only, date, display name)
- [ ] Player surface selected by explicit context (`activeMediaKind`, never `currentChannel?.mediaKind ?? .music`)
- [ ] Finite non-ambient surfaces expose elapsed, remaining, and scrubber
- [ ] Audiobook/lecture surfaces expose work-level time left
- [ ] MP3-only policy enforced; no Ogg/FLAC/M4A/AAC/Opus/WAV/SHN in playback selectors
- [ ] `xcodegen generate` run if files added/removed
- [ ] Unit tests pass: `xcodebuild test ... -only-testing:ParsoMusicTests`
- [ ] `RegressionContractSourceTests` pass (no banned patterns reintroduced)
- [ ] UI changes: targeted UI test or simulator screenshot evidence attached

### Notes

