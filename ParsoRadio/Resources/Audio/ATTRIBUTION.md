# Ambient Loop Assets — bundled, offline, gapless

These WAV files ship in the app bundle. `AmbientStaticService.bundledLoopURL`
→ `PlayerViewModel.playTrack` plays the local file (no network), and PCM WAV
loops with no encoder-padding click. The Freesound HQ-mp3 preview is only a
fallback if a file is ever missing.

| File                          | Source (CC0, Freesound)                                    |
|-------------------------------|------------------------------------------------------------|
| `ambient-flowing-water.wav`   | eardeer — https://freesound.org/people/eardeer/sounds/443869/   |
| `ambient-rain.wav`            | svampen — https://freesound.org/people/svampen/sounds/334149/   |
| `ambient-ocean.wav`           | Nox_Sound — https://freesound.org/people/Nox_Sound/sounds/829629/ |

All three sources are CC0 (public domain).

## How they were produced

Freesound's public CDN only serves lossy mp3/ogg previews (the original WAV
needs an authenticated OAuth2 download). Each file here was made by decoding
the CC0 HQ-mp3 preview to PCM (removing the MP3 encoder delay/padding that
caused the loop click), capping length to ≤30 s, and applying a 0.75 s
equal-power crossfade of the tail into the head so the buffer wraps onto
itself **seamlessly** regardless of the source's own loop points. Output is
16-bit PCM stereo @ 44.1 kHz.

Regenerate with `/tmp/mkloops.py` (decode → central window → equal-power
crossfade → WAV). To shrink further, convert to CAF — the resolver prefers
`.caf` over `.wav`:

```
afconvert -f caff -d LEI16@44100 ambient-rain.wav ambient-rain.caf
```

XcodeGen bundles everything under `ParsoRadio/` automatically — no project
edits needed.
