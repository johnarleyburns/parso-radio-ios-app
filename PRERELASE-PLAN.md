# Pre-Release Plan — Parso Radio

Gap analysis of music-player features that the app is missing, ranked by
impact for the actual content mix (audiobooks, lectures, news, radio,
ambient). Grounded in Apple HIG and what comparable apps ship (Apple
Music, Audible, Overcast, Pocket Casts).

## Tier 1 — high impact for this app's content mix

1. **Variable playback speed (0.5×–2×).** The #1 missing feature for an app
   with audiobooks and lectures. `AVPlayer.rate` plus a speed picker
   (0.5 / 0.75 / 1× / 1.25 / 1.5 / 1.75 / 2×) in the More Options sheet.
   Audible / Overcast users expect this; some can't tolerate 1× on a long
   book.

2. **Sleep timer.** Universally expected, especially for ambient channels
   and bedtime audiobooks. Standard options: 15 / 30 / 45 / 60 min / End
   of Track / Custom. One `Task.sleep` → `audioPlayer.pause()`.

3. **Lock-screen ±15 s skip buttons (for spoken-word channels).**
   `MPSkipBackwardCommand` / `MPSkipForwardCommand` with
   `preferredIntervals = [15]`. The lock screen currently only does
   next / previous *track*, which on a 12-hour audiobook is wrong.
   Per-channel: time skip for `.spokenWord`, track skip otherwise.

4. **Chapter list for the currently-playing multi-part book.**
   `currentTrackIsMultiPart` is already detected. Add a "Chapter List"
   row to the More Options sheet → list of all parts with the current
   one highlighted; tap to jump. Today the only way to navigate within
   a book is to add the whole book to a playlist first.

## Tier 2 — standard, low-effort wins

5. **Recently Played view.** The `track_play_history` table is already
   populated and unused in the UI. A "Recently Played" section in
   MainMenu (last 20–50 tracks, tap to replay) costs almost nothing to
   surface.

6. **AirPlay button in the player.** `AVRoutePickerView`
   (system-provided). AirPlay works via Control Center today, but
   in-app discoverability is poor.

7. **Share track.** `ShareLink` with the `archive.org/details/<id>` URL.
   App Review reviewers also like to see this on content apps.

8. **Mini-player at the bottom of the MainMenu sheet.** Opening the menu
   fully covers the now-playing screen; a small sticky bar
   (artwork + title + play/pause) would match the Apple Music /
   Spotify pattern.

## Tier 3 — nice-to-have

9. **Bookmarks within a long track** (audiobook timestamps). Could reuse
   the positions table.

10. **Smart Speed / silence trimming** for spoken content
    (Overcast-style). Real work; skip for v1.

11. **Equalizer / bass boost.** Power-user feature; rarely worth it in a
    1.0.

12. **iCloud Resume sync.** Would need accounts; explicitly out of scope.

## Tier 4 — polish before the first review wave

13. **Dynamic Type.** The main page now uses fixed 19 pt / 14 pt. Apple's
    HIG strongly favors Dynamic Type. Consider clamping with
    `.dynamicTypeSize(.medium ... .accessibility2)` instead of fixed
    `.system(size:)` — keeps the layout but respects user text-size
    settings. Real-world accessibility win on top of the VoiceOver work
    already shipped.

14. **Reduce Motion support.** Pause/skip the procedural visualizer
    animations when the OS setting is on
    (`@Environment(\.accessibilityReduceMotion)`).

## What is already shipped (not missing)

- Now Playing artwork + remote commands
- Offline downloads
- Resume (now correctly to the offset, including long audiobooks
  post-upgrade)
- CarPlay
- Search history and recents
- DMCA reporting + per-track license display
- Procedural visualizer fallback when artwork is missing
- Universal (iPhone + iPad)
- Multi-part book detection and "Add Book to Playlist"
- Full VoiceOver accessibility
- Zero compiler warnings

## Recommended cut for the first App Store submission

Ship items **#1 (variable speed)**, **#2 (sleep timer)**, and
**#3 (lock-screen ±15 s for spoken)**. Together they are roughly a day of
work and they erase the biggest "this is missing" reactions reviewers and
audiobook listeners will have. Everything else (4–14) is fine as v1.1
or v1.2.
