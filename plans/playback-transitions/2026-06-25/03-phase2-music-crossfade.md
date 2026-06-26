# Phase 2 — True Music Crossfade

Date: 2026-06-25
Branch: `playback-transitions-phase2` (off `main`, Phase 1 merged)
Status: implementing

## Problem

Phase 1 gives music→music natural advance a short fade-in from silence, but the
outgoing track has already ended — there is no overlap, so back-to-back songs
still have a brief gap. Music-player norms (Apple Music Crossfade, Spotify
Crossfade) overlap the tail of one song with the head of the next.

## Current Behavior

`AudioPlayerService` drives a single `AVPlayer`. Natural advance fires at the
real end (`AVPlayerItemDidPlayToEndTime` → `onTrackFinished` → VM
`advanceToNext` → `playTrack` → `audioPlayer.play(..., transition:)`). Phase 1's
policy returns `.fadeIn(0.2)` for music natural advance, so the new track fades
in over already-silent output. `prefetchNextURL` resolves the next channel
track's URL after the current track starts, so the next URL is usually warm.

## Research Signal

Apple Music and Spotify both ship music-only crossfade (~1.5–3 s overlap) and
explicitly do NOT crossfade spoken content. (See `00-overview.md` sources.) Our
decision sheet picked: Settings toggle, default ON, fixed 2.0 s, music radio
channels only.

## Design

Keep ONE primary `AVPlayer`. Add a crossfade that overlaps the outgoing tail
with the incoming head, reusing the entire VM advance flow:

```text
music-channel track playing, crossfade armed (lead = 2s)
        |
   time observer crosses (duration - 2s)   <-- EARLY trigger (repeatMode .off)
        |  detach end observer, keep playing
        v
   onTrackFinished()  -> VM advanceToNext(.naturalAdvance)
        |
        v
   playTrack(nextMusic, .naturalAdvance) -> style .musicCrossfade(2.0)
        |
        v
   AudioPlayerService.play(..., .musicCrossfade(2.0))
        |  current player still .playing?
        |---- yes --> crossfadePlay: demote outgoing -> 2nd player, ramp it 1->0;
        |             build new primary, start at 0, ramp 0->1; tear down outgoing
        |---- no  --> fall back to normal play with fade-in (Phase 1 behavior)
```

Why early-fire instead of a prepared-next dual player: it reuses 100% of the VM
advance/bookkeeping flow and the existing prefetch, touching only
`AudioPlayerService`. The incoming item builds on demand; if it isn't live within
the lead window the path degrades to a Phase 1 fade-in (no regression, just no
overlap that time).

Engine surface:
- `armCrossfade(leadSeconds:)` — fire natural advance `leadSeconds` early for the
  current item (0 disarms). Reset to 0 on every teardown.
- `play(..., transition: .musicCrossfade(d))` — if a live primary player is
  `.playing`, run `crossfadePlay` (overlap); else normal play (fade-in `d`).

`crossfadePlay` is an isolated method (does NOT refactor the shipped normal
`play` body) so Phase 1's audio path is untouched. It demotes the current
player/caching-delegate/observers to `outgoing*` slots, ramps the outgoing down
on a dedicated `crossfadeOutTask`, builds a fresh primary player (its own caching
delegate + observers + token) starting at volume 0 with `pendingFadeIn = d`, and
tears the outgoing down when its ramp completes. Every new play/skip/teardown/
pause/route/interruption cancels both ramp tasks and tears down the outgoing.

Policy: `style(..., crossfadeMusic: Bool)`. music→music `.naturalAdvance` returns
`.musicCrossfade(2.0)` when `crossfadeMusic`, else `.fadeIn(0.2)`. Manual/spoken/
ambient/mixed are unaffected.

VM: reads `musicCrossfadeEnabled` (UserDefaults, absent ⇒ true). In `playTrack`,
`crossfadeMusic = musicCrossfadeEnabled && currentChannel?.mediaKind == .music`
flows into the policy; after committing a music-channel track it calls
`armCrossfade(leadSeconds: 2.0)`, otherwise `armCrossfade(leadSeconds: 0)`.

## Data-Model Deltas

None. New UserDefaults key `musicCrossfadeEnabled` (Bool, default true via
`@AppStorage`). No DB migration.

## Implementation Steps

1. Policy: add `crossfadeMusic` param + `.musicCrossfade(2.0)` for music natural
   advance. Update `PlaybackTransitionPolicyTests`.
2. Engine protocol: add `armCrossfade(leadSeconds:)`.
3. `AudioPlayerService`: store `crossfadeLeadSeconds` + `didFireEarlyFinish`;
   early-fire in the periodic time observer (repeatMode .off only); `crossfadePlay`
   + `outgoingPlayer`/`outgoingCachingDelegate`/`crossfadeOutTask` + teardown.
4. `FakeAudioEngine`: record `armCrossfade` (`lastCrossfadeLead`).
5. VM: setting read, thread `crossfadeMusic` into the policy, arm/disarm after play.
6. Settings: `Toggle` "Crossfade Music" (`@AppStorage("musicCrossfadeEnabled")`).
7. Tests + build + `ParsoMusicTests`.

## Testing Strategy

- Policy matrix: musicCrossfade only when `crossfadeMusic && music→music &&
  naturalAdvance`; manual/spoken/mixed/ambient never crossfade.
- `FakeAudioEngine` records `armCrossfade` lead.
- True audio overlap is manual QA on device (headless tests can't validate two
  mixed AVPlayers): music channel auto-advance overlaps; manual next does not;
  toggle off restores Phase 1 fade; skip/pause/seek during the lead window behave;
  ambient/audiobook unaffected.

## Open Questions

- Extend crossfade to pure-music playlists once channel crossfade proves out?
- Equal-power (cosine) ramp vs. linear — start linear, revisit if it sounds dippy.
