# Kids Mode — Navigation Audit (Plan)

Companion to `KIDS-MODE-PLAN.md`. The mission: a child handed the phone in Kids
Mode cannot reach any non-kid content, by any path, **ever**. This document
enumerates every surface I can see, the current status, and the open work
(item 6 from the test-feedback list).

Status legend: ✅ blocked · 🟡 partial / verify on device · 🟥 known gap

## Reachable from the wheel

| Surface | Status | Notes |
|---|---|---|
| Wheel MENU → KidsMenuView | ✅ | `iPodView.openMenu(contextual:)` short-circuits to `showKidsMenu = true` when `kids.isEnabled`. |
| Wheel ±10 / next / prev / play-pause | ✅ | Bounded to current channel/playlist; cannot select a foreign channel. |
| Wheel center → Track Info | 🟡 | Sheet opens, but **all modifying actions hidden** (bookmarks, share, favorites, add-to-playlist, add-book/album-to-playlist, add-to-new-playlist, screen-panel context "Add to Playlist"). Playback controls + Play Entire Album/Book stay. Confirm none re-appears in any edge case. |

## Reachable inside `KidsMenuView`

| Surface | Status | Notes |
|---|---|---|
| Children's Songs / Children's Books rows | ✅ | Load channel + dismiss menu. |
| "My Playlists" section | ✅ | Only `playlistVM.kidSafePlaylists` listed. |
| Tap a kid-safe playlist → PlaylistDetailView | ✅ | Push onto SAME NavigationStack ⇒ Back returns to KidsMenuView. |
| PlaylistDetailView in Kids Mode | 🟡 | EditButton, "Add to Playlist…", Kid-Safe toggle all gated `if !kids.isEnabled`. Verify: swipe-to-delete cannot fire (no EditMode); tap-track-to-play still works (intentional — playback, not editing). |
| Lock button → PIN alert | ✅ | Correct PIN exits; wrong PIN shows "Wrong PIN" and Kids Mode stays on. |

## Playback engine paths (lock-screen / AirPods / Now Playing)

| Surface | Status | Notes |
|---|---|---|
| Lock-screen play/pause/seek | ✅ | Acts on current track only. |
| Lock-screen next/prev | 🟡 | Calls `onTrackFinished` / `onPreviousTrack` → `advanceToNext` / `playPreviousTrack`. On a kids channel: stays in channel pool (kids content). On a kid-safe playlist: stays in `playlistTracks`. `playHistory` is cleared on enable, so previous can't reach pre-Kids-Mode tracks. **Risk:** `playHistory` re-accumulates during the session — re-verify it can never contain a non-kid track. |
| `restoreLastSession` on cold launch | ✅ | iPodView's `.task` skips it and loads a kids channel + auto-shows kids menu when `kids.isEnabled`. |
| Background interruption resume | ✅ | `AudioPlayerService.handleInterruption(.ended)` resumes the current item only. |
| `audioPlayer.skip()` on track switch | ✅ | Mechanic only; doesn't pick the next track. |

## Sheets / NavigationLinks NOT reachable in Kids Mode

| Surface | How it's blocked |
|---|---|
| MainMenuView (full library + categories + Search) | The wheel MENU never opens it (`openMenu` branches on `kids.isEnabled`). |
| `showSearch`, `showChannelSelector`, `showPlaylists`, `showAbout` | Triggered only from MainMenuView; not reachable. |
| SettingsView | Reached only from MainMenuView's `.settings` route; not reachable. |
| ChannelInfoView | Reached only from MainMenuView's `.channelInfo` route; not reachable. |
| Recently Played | Same. |
| ContributionSupportView / toast | Toast suppressed in `ParsoRadioApp.body` overlay when `kids.isEnabled`; `evaluate()` also gated. |
| AddTracksView | Only via PlaylistDetailView's "Add to Playlist…" — hidden in Kids Mode. |

## Open items (the actual TODO for the next pass)

1. **Verify on-device** every 🟡 above is actually blocked, end-to-end. SwiftUI
   gating is correct in source; a device walk-through is the empirical proof.
2. **`playHistory` audit.** Trace every place that pushes to `playHistory`
   (`playTrack(recordHistory:)`, `advanceToNext`) and confirm in Kids Mode the
   history can ONLY contain tracks from kids channels or kid-safe playlists.
   Add a unit test: clear → enter kids → play a sequence → assert every
   `playHistory` entry has a kid-safe origin.
3. **Favorites playlist** is currently *un-markable* as kid-safe (the toggle is
   hidden when `playlist.isFavorites`). Decide: should parents be able to mark
   Favorites kid-safe too? If yes, drop the `!playlist.isFavorites` guard and
   ensure Favorites' read-only behavior holds in Kids Mode.
4. **PlaylistDetailView tap-to-play in Kids Mode** — currently allowed
   (playback, not editing). If you'd rather only allow Resume / Shuffle / Play
   from top, gate the row `onTapGesture` on `!kids.isEnabled`.
5. **`audioPlayer.repeatMode` carryover** — if the parent had `.one` set
   pre-Kids-Mode, it persists. Acceptable, but document.
6. **Save/restore (`saveCurrentSpot`, `persistSession`) while in Kids Mode** —
   confirm the saved channel/playlist on resign is always kid-safe, so the
   next launch's restore-then-redirect can't briefly show a non-kid item.
7. **Track Info → Chapter List → tap chapter** — chapters of a multi-part item
   the kid is already playing; stays within the item. ✅, but include in test
   to be explicit.
8. **Lock-screen artwork tap** doesn't deep-link in iOS, but confirm no
   `userActivity` / handoff path can route back into the app on a non-kid
   track.
9. **Tests to add (item 6):**
   - `KidsModeNavigationTests` — programmatically construct each "would this
     view appear?" predicate per surface and assert under `kids.isEnabled`.
   - `PlayHistoryNeverContainsNonKidWhenKidsModeOn` — drive the player
     through a scripted session.
   - `EnableKidsMode_DropsPlaylistContext_IfNotKidSafe` — covered conceptually
     by the iPodView `.onChange` redirect; lift the predicate into a pure
     function and unit-test it (same pattern as `shouldRedirect`).
10. **Programmatic invariant guard (optional).** A small DEBUG-only assertion
    that, whenever `kids.isEnabled`, the `currentChannel` is in
    `KidsModeController.allowedChannelIDs` OR the `currentPlaylist?.isKidSafe`
    is true. Catches any leak we missed during manual testing.

## Process: how to use this list

Each open item becomes a small named commit. The next time we touch Kids Mode,
walk top-to-bottom and tick each off — then mark this doc "audit complete"
with the build number it was verified on.
