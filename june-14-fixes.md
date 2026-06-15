# June 14 Fixes Plan — COMPLETED

## 1. ✅ "Time left in book" showing on music tracks
**Fix:** Added `behavior.supportsBookSkip` guard in NowPlayingSheet progressSection.

## 2. ✅ "Music for You" - add "play entire album" icon
**Fix:** Added `opticaldisc` icon button next to `plus.circle` in music-mode row. Opens `AlbumTracksSheet` with track list and "Play Entire Album" option.

## 3. ✅ Music player layout: << left-justified, >> right-justified, heart ABOVE elapsed, share ABOVE remaining
**Fix:** TransportControls uses `Spacer()` for edge alignment. progressSection reverted to VStack layout (heart above elapsed, share above remaining).

## 4. ✅ Audiobook view overflowing screen
**Fix:** Removed `.frame(maxWidth: .infinity)` from actionButtons items, used `Spacer()` for distribution, reduced AirPlay to 28×28, Safari to `.body` font.

## 5. ✅ No sound after switching apps (AVAudioSession)
**Fix:** Interruption `.shouldResume` now calls `resume()` which handles `setActive`, `pendingAutoPlay`, `applyRate()` in one robust method.

## 6. ✅ "Jump Back In" at top of Listen — verified + tested
**Status:** JumpBackInSection EXISTS at ListenView.swift:24. Added 2 new tests in RecentlyPlayedTests: `testJumpBackInShowsAfterPlayingTrack` and `testJumpBackInEmptyForFirstTimeVisitor`. All 9 tests pass.

## 7. ✅ "Books for You" fallback when <5 chapters
**Fix:** Added `fetchFallbackTracks(for:)` to RecommendationsController. When <minPlays, falls back to random tracks from Audiobooks/Curated category channels.

## 8. ✅ "Music for You" fallback when <5 tracks
**Fix:** Same `fetchFallbackTracks(for:)` handles both "music-for-you" (Curated channels) and "books-for-you" (Audiobooks channels).

## 9. ✅ Podcast player alignment
**Fix:** Same TransportControls spacer-based layout applies to all non-music modes.

## 10. ✅ Curator loading lockup
**Fix:** Added `await Task.yield()` in AuditionController.auditTrack after `beginTransition()` so UI updates (loading spinner) before heavy `playTrack` work.

## Files modified
- `ParsoRadio/Views/Player/NowPlayingSheet.swift` — layout overhaul, album tracks sheet
- `ParsoRadio/Views/Player/TransportControls.swift` — edge-aligned spacer layout
- `ParsoRadio/Core/Services/Playback/AuditionController.swift` — Task.yield()
- `ParsoRadio/Core/Services/Playback/AudioPlayerService.swift` — resume() in interruption
- `ParsoRadio/Core/Services/Playback/RecommendationsController.swift` — fallback tracks
- `ParsoRadio/ViewModels/PlayerViewModel.swift` — fallback in load()
- `ParsoRadio/Core/Tests/RecentlyPlayedTests.swift` — 2 new Jump Back In tests
