# Refinements — New Round (2026-05-22)

Plan for the 11 requested changes. Implementation follows this doc.

## 1. Playlist order reversal (CRITICAL bug)

**Root cause:** `DatabaseService.setTrackOrder(_:inPlaylist:)` writes
`sort_order = index` (ascending), but `fetchTracks(forPlaylist:)` reads
`ORDER BY sort_order DESC`. So any reorder (or onMove) reverses the list.
`addTracksOrdered` already compensates by writing descending values; only
`setTrackOrder` was inconsistent.

**Fix:** write descending in `setTrackOrder` (`sort_order = count - index`)
so the on-screen order is preserved under the DESC fetch. Unit test added
(`PlaylistOrderTests`): add an ordered book, reorder, re-fetch, assert order
is exactly what was set (not reversed).

## 2. Classical Guitar → Spanish-composer, guitar-only

The performer+broad-subject query let in non-guitar (lute early-music) and
radio/talk noise. Replace with a Spanish-composer / Spanish-guitarist query:
recognized classical guitarists (Segovia, Yepes, Romeros, Sainz de la Maza,
Bream, Tárrega, Paco de Lucía, Sabicas, Montoya, Barrueco, Russell, Li Jie)
+ the `"Spanish guitar"` / `"classical guitar"` / `"flamenco guitar"`
subjects + iconic Spanish guitar works by title (Recuerdos de la Alhambra,
Concierto de Aranjuez, Asturias). Exclude orchestral / piano / violin /
cello / trio / quartet / lute / vocal / radio / talk / lesson. Curl-verified
2026-05-22 — 299 items, almost entirely solo Spanish guitar. Update the
summary + ChannelTests.

## 3. Wheel center → Track Info (no repeat, no icon)

Remove the phantom repeat-one toggle and its centre glyph. Centre tap now
opens the Track Info sheet. ClickWheel loses `repeatEnabled/repeatOn/
onRepeatToggle`; gains `onCenter`.

## 4. Wheel forward/back: tap / double-tap / hold (iPod-style)

For the left (back) and right (forward) wheel regions:
- **Single tap** → seek ∓10 s within the track.
- **Double tap** → previous / next *track*.
- **Press & hold** → continuous scrub within the track, accelerating the
  longer it's held (like the classic iPod). Release stops.

Implemented with a per-region DragGesture state machine: a 0.35 s timer
distinguishes hold from tap; a 0.3 s window distinguishes single from double
tap (single-tap action is deferred by that window). Hold runs a repeating
timer that advances a local scrub position by a growing step and calls
`onSeek`, with `onScrubChanged` gating the VM's time updates.

## 5. Reliable back-skip history on channels

**Root cause:** channel history (`playHistory`) is pushed inside `playTrack`
only when `currentTrack` is still set; the min-duration screening path nils
`currentTrack` first, and some flows can miss it — so double-tap-back lands
on a fresh random pick.

**Fix:** capture the outgoing track at the very top of `advanceToNext` and
push it onto `playHistory` explicitly (deduped, capped at `historyLimit`),
with the per-flow `playTrack` calls switched to `recordHistory: false` to
avoid double counting. `playPreviousTrack` pops this stack. Unit test for a
multi-step forward-then-back sequence returning the exact prior tracks.

## 6. Remove favorites icon + target on the track box

Delete the heart button from the scrubber control row (and its
toggleFavorite plumbing on the track box; favorites remain reachable via
playlists).

## 7. Remove the track-box tap zones

Delete `centerTapZones` entirely (the −10/＋10/play-pause band). Those
actions now live on the wheel.

## 8a. Remove the ••• info button on the track box

Delete the More-Options button from the scrubber row. The wheel centre now
opens Track Info.

## 8b. Repeat = a "Repeat Track" toggle in Track Info + corner icon

Add a "Repeat Track" toggle to the Track Info sheet (Playback section). When
on, show a small `repeat.1` icon in the upper-right of the track box; when
turned off it disappears and playback is normal. Ambient loops don't show
it (they already loop).

## 9. Inline search (no separate screen)

Replace the Search sheet with an inline search field on the menu
(`.searchable`). While the query is non-empty, the category / playlist /
recently-played sections are hidden and IA search results render in their
place (driven by the existing SearchViewModel); clearing the field restores
the menu. Result rows keep their play / add-to-playlist actions.

## Validation

- `swiftc -parse` every changed Swift file.
- Curl-verify the new guitar query (done — 299 items).
- New unit tests: PlaylistOrderTests, channel back-history, plus existing
  ChannelTests / search tests updated to the new guitar query.
- Push, watch CI, iterate to green.
