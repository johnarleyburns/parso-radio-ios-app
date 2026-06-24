# Music For You + Player Surface Fixes — Overview

Date: 2026-06-24
Branch/PR: single phase, `fix/music-for-you-and-player-surfaces` → merge to `main`.

## Raw notes / reported problems

1. Home "Made for you" shelf uses a different header font/layout than the other
   sections (it has a `sparkles` icon and `.headline.weight(.semibold)`), and the
   header only appears once loaded. It should look like "Jump back in" / "Explore"
   / "Featured today" / "A Book Curated For You": a plain section header, no icon.
2. The shelf does not load immediately on startup — it briefly shows an
   empty/"can't find" state and only fills in later. It should show a spinner
   while it is fetching and fill in as soon as data is ready.
3. Rename "Made For You" → "Music For You" and return **music tracks only** —
   never LibriVox audiobooks, podcasts, or lectures.
4. "A Book Curated For You" should sit directly below "Music For You".
5. The **music** and **audiobook** player surfaces are missing the elapsed time /
   remaining time / progress slider that the podcast and lecture surfaces have.
   Put them back.
6. The **Download** action should live in the player overflow (ellipsis) menu for
   every kind **except ambient looping**, where it is currently missing.

## Grounding — exact files touched

| Area | File |
| --- | --- |
| Home shelf order | `ParsoRadio/Views/Listen/ListenView.swift` |
| Shelf header/states | `ParsoRadio/Views/Listen/MadeForYouSection.swift` |
| Shelf music-only + cold start | `ParsoRadio/Core/Services/Playback/MadeForYouShelfStore.swift` |
| Recommendations music-only | `ParsoRadio/Core/Services/Playback/RecommendationsController.swift` |
| Music scrub bar | `ParsoRadio/Views/Player/Controls/MusicControls.swift` |
| Overflow download | `ParsoRadio/Views/Player/NowPlayingSheet.swift` |
| Source guard test | `ParsoRadio/Core/Tests/RegressionContractSourceTests.swift` |
| Contract doc | `AGENTS.md` |

## Cross-cutting decisions

- **Do NOT flip `MediaKind.music.behavior.showsScrubbableProgress`.** That flag is
  overloaded: it drives the audio content mode (`PlayerViewModel.swift:501`
  `setContentMode(... ? .spokenWord : .music)`) and resume-position logic
  (`:867`). Flipping it for music would change audio-engine behavior and break
  `MediaKindTests` / `PlayerPerKindControlsTests`. Instead the music **view**
  renders `ScrubRow` unconditionally, independent of the behavior flag. The
  `ScrubBar` already degrades to a linear `ProgressView` when `trackDuration`
  is nil, so continuous streams stay correct.
- **Audiobook already renders `ScrubRow`** via `SpokenControls(... showTimeLeftInWork: true)`.
  No code change is needed there; the only real regression is `MusicControls`,
  which lost its scrub row in commit `21e7db3`. We still re-verify audiobook.
- **Music-only is enforced query-side**, not by post-hoc `mediaKind` filtering.
  A LibriVox audiobook fetched for-you has `source == "internet_archive"` and no
  channel, so `Track.mediaKind(in: nil)` resolves to `.music` and a filter would
  miss it. The fix removes spoken-word queries entirely: skip the `spoken`
  taste-profile queries and drop the `collection:librivoxaudio` cold-start query.
  A defensive `source` filter (drop `podcast` / `oxford_lectures`) is added too.
- **Overflow Download needs `OfflineDownloadService`.** It is injected at app root
  on `RootTabView` and `KidsHomeView` and propagates through the environment into
  the presented `NowPlayingSheet` (proven: `KidsHomeView` presents the sheet
  injecting only `playerVM`, yet the sheet reads `favorites`). `NowPlayingSheet`
  adds `@EnvironmentObject var offlineService`; the easy presentation sites also
  inject it explicitly for belt-and-suspenders.

## Roadmap

Single phase, single PR. See `01-design.md` for the per-problem anatomy and
`02-rollout.md` for the phased table + verification gate.
