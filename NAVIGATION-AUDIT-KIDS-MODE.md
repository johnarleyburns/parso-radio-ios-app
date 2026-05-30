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

## Open items (TODO + progress log)

1. **Verify on-device** every 🟡 above is actually blocked, end-to-end. SwiftUI
   gating is correct in source; a device walk-through is the empirical proof.
   *Status: open — every TestFlight build should include a quick walk.*
2. **`playHistory` audit.** Trace every place that pushes to `playHistory`
   (`playTrack(recordHistory:)`, `advanceToNext`) and confirm in Kids Mode the
   history can ONLY contain tracks from kids channels or kid-safe playlists.
   *Status: open — needs a scripted-session test using the existing
   `FakeAudioEngine` harness.*
3. ✅ **Favorites kid-safe** — *Decision: ALLOWED.* The toggle now appears on
   every playlist including Favorites. Read-only-in-Kids-Mode behavior already
   holds (the EditButton is gated globally on `!kids.isEnabled`).
4. **PlaylistDetailView tap-to-play in Kids Mode** — *Decision: kept enabled*
   (playback, not editing). Documented as the explicit policy.
5. **`audioPlayer.repeatMode` carryover** — *Documented.* If the parent had
   `.one` set pre-Kids-Mode, it persists. Acceptable.
6. **Save/restore (`saveCurrentSpot`, `persistSession`) while in Kids Mode** —
   *Status: open.* Verify on device that the saved playlist on resign is always
   kid-safe (kid-safe playlists are preserved on enable as of this audit, so
   the resign path is the next thing to confirm).
7. **Track Info → Chapter List → tap chapter** — stays within the item. ✅
   *Add an explicit test* (still open).
8. **Lock-screen artwork tap / `userActivity` / handoff** — confirm no path
   surfaces a non-kid track. *Status: open — device verification.*
9. **Tests to add:**
   - ✅ `KidsModeNavigationTests` — `shouldRedirect`, `needsRedirect`,
     `invariantHolds` cases (this audit).
   - ✅ `EnableKidsMode_DropsPlaylistContext_IfNotKidSafe` — covered by the
     `needsRedirect_*` test cases.
   - **Still open:** `PlayHistoryNeverContainsNonKidWhenKidsModeOn` — scripted
     session via `FakeAudioEngine`.
10. ✅ **Pure invariant predicate exposed.**
    `KidsModeController.invariantHolds(currentChannelId:currentPlaylistIsKidSafe:)`
    is the single source of truth — usable for a DEBUG `assertionFailure` at
    each context transition, or for property-based fuzzing. Hook-up to a
    runtime guard is a follow-up.

### Helpers exposed by this audit

```swift
// Single decision for "enabling/maintaining Kids Mode requires redirect?"
KidsModeController.needsRedirect(currentChannelId:, currentPlaylistIsKidSafe:)

// The runtime invariant: allowed channel OR kid-safe playlist.
KidsModeController.invariantHolds(currentChannelId:, currentPlaylistIsKidSafe:)
```

Both are unit-tested across the relevant cases and now drive the iPodView
`.onChange(of: kids.isEnabled)` redirect — so a kid-safe playlist context is
preserved when Kids Mode flips on (a parent can hand the phone over without
interrupting an already-curated kid playlist).

## Process: how to use this list

Each open item becomes a small named commit. The next time we touch Kids Mode,
walk top-to-bottom and tick each off — then mark this doc "audit complete"
with the build number it was verified on.
