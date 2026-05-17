# Ambient Loop Assets — offline-by-default, gapless

Drop the three loop files here, named **exactly** by channel id. The app
(`AmbientStaticService.bundledLoopURL` → `PlayerViewModel.playTrack`) prefers a
bundled file over the network and, for PCM/lossless formats, loops it with no
seam. Preferred order: `.caf` › `.wav` › `.aiff` › `.m4a` › `.aac` › `.mp3`.

| Channel id              | Required file (any preferred ext) | Source (CC0, Freesound)                                   |
|-------------------------|-----------------------------------|-----------------------------------------------------------|
| `ambient-flowing-water` | `ambient-flowing-water.wav`/`.caf`| eardeer — https://freesound.org/people/eardeer/sounds/443869/   |
| `ambient-rain`          | `ambient-rain.wav`/`.caf`         | svampen — https://freesound.org/people/svampen/sounds/334149/   |
| `ambient-ocean`         | `ambient-ocean.wav`/`.caf`        | Nox_Sound — https://freesound.org/people/Nox_Sound/sounds/829629/ |

## Why these aren't auto-downloaded

Freesound's public CDN only serves **lossy mp3/ogg previews**; the original
WAV requires an authenticated OAuth2 API download. Streaming the mp3 preview
(the current fallback) also re-introduces the ~26–52 ms LAME encoder
delay/padding gap at every loop point, and needs the network.

Committing the real WAV/CAF here is the only way to get **gapless** loops that
work **offline from first launch**. Convert to CAF for best results, e.g.:

```
afconvert -f caff -d LEI16@44100 ambient-rain.wav ambient-rain.caf
```

XcodeGen bundles everything under `ParsoRadio/` automatically — no project
edits needed once the files are added.
