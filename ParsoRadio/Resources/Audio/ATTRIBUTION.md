# Ambient Loop Assets — bundled, offline, gapless

These WAV files ship in the app bundle. `AmbientStaticService.bundledLoopURL`
→ `PlayerViewModel.playTrack` plays the local file (no network), and PCM WAV
loops with no encoder-padding click. The Freesound HQ-mp3 preview is only a
fallback if a file is ever missing.

| File                          | Author / License | Source (Freesound)                              |
|-------------------------------|------------------|-------------------------------------------------|
| `ambient-flowing-water.wav`   | eardeer · **CC0**     | https://freesound.org/people/eardeer/sounds/443869/   |
| `ambient-rain.wav`            | svampen · **CC BY 3.0** | https://freesound.org/people/svampen/sounds/334149/ |
| `ambient-ocean.wav`           | Nox_Sound · **CC0**   | https://freesound.org/people/Nox_Sound/sounds/829629/ |

eardeer/443869 and Nox_Sound/829629 are CC0 (public domain).

> ⚠️ **OUTSTANDING — rain AUDIO is still CC BY 3.0.** `ambient-rain.wav` is
> derived from svampen/334149 (CC BY 3.0); the previously-used rain source
> DWOBoyle/136971 is CC BY 4.0 — so there is no drop-in CC0 rain audio. To
> make the app **all-CC0**, a CC0 rain sound must be chosen to regenerate
> `ambient-rain.wav` and reset its license to `.cc0`. Until then attribution
> for svampen is required (shown via track License/Artist + About → Credits).

### Background videos (`Resources/Video/ambient-*.mp4`)

| File | License |
|---|---|
| `ambient-rain.mp4` | **CC0** (user-supplied `100925-video-720.mp4`) |
| `ambient-flowing-water.mp4` | Mixkit Free License — confirm before release |
| `ambient-ocean.mp4` | Mixkit Free License — confirm before release |

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
