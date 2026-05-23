# Revisions — May 22 (round B)

## 1. Back button bounces into Channel Info (severe)
Root cause: MainMenuView pushes `initialRoute` inside an async `.task` AFTER
`await recentlyPlayedTracks()` and guarded only by `path.isEmpty`. If the
user taps Back during that ~0.5 s await, the await then completes and re-pushes
the route. Fix: seed `path` from `initialRoute` synchronously in an `init`
(no async push, no re-push), and drop the push from `.task`.

## 2. "Playlists" header has no icon
The Playlists collapsible header was created without an icon. Add
`music.note.list`.

## 3. "Edit" should be on the Playlists row only
Remove the nav-bar `EditButton`. Put an Edit/Done control in the Playlists
header's trailing slot (only while expanded), since only playlists are
reorderable/deletable. Recently Played keeps swipe-to-delete + Clear-All.

## 4. Replace Classical Guitar with a strict Spanish Guitar channel
Remove `classical-guitar`; add `spanish-guitar` ("Spanish Guitar"). Query
(curl-verified 2026-05-22, len 1384, 219 items) matches ONLY:
- renowned classical guitarists (Segovia, Yepes, Bream, the Romeros, Sainz
  de la Maza, Tárrega, Paco de Lucía, Sabicas, Montoya, Barrueco, Russell,
  Parkening, Vidović, Isbin, Li Jie), whose catalogue is all guitar; OR
- explicit title phrases "classical/spanish/flamenco guitar", "guitar recital"; OR
- top Spanish-style guitar composers (Sor, Albéniz, Granados, Rodrigo,
  Barrios, Ponce, Villa-Lobos, Brouwer) GATED to title:guitar/guitarra.
Excludes orchestra/piano/violin/cello/lute/vocal/opera/electric/rock/pop/
jazz/electronic/dance/new-age/soundtrack + radio/podcasts. This drops the
loose `subject:"classical guitar"` arm that leaked "Joy Bells by Cliff
Friend". Update Channel.swift (id/name/summary), ia_queries.json,
ChannelTests + the IAQueryRegistry/QueueManager/PlayerViewModel test refs.

## 5. Track Info action order
Reorder the actions section to: Share Track → Add to Favorites → Add to
Playlist (Favorites moves under Share, above Add to Playlist).

## 6. "Loading" must persist until audio truly starts
Today `isLoading=false` is set right after `audioPlayer.play()` returns —
seconds before audible playback. Keep it true and clear it on the FIRST
periodic time-observer tick (which only fires once the player is actually
progressing). Ambient loops clear immediately (bundled, instant). Failures
already clear via handleLoadFailure.

## (separately) Considered for NEXT round, not now
Drill-down menu navigation (tap a category → pushed Channels list) instead
of inline expansion — recommended per HIG, but deferred until confirmed.

## Validation
swiftc -parse; curl done; update tests; push as one batch; iterate to green.
