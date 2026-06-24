# 03 - Player Surfaces And Time Controls

## Problem

The app has separate player controls for music, audiobooks, podcasts, lectures, and ambient content, but direct launch paths can bypass the intended surface. When a book or spoken-word sequence launches with `currentChannel == nil`, `NowPlayingSheet` defaults to `.music`, which can hide book-specific time controls and show the wrong transport model. Separately, every finite non-ambient surface must retain elapsed time, remaining time, and scrubber control.

## Current Behavior

Physical files involved:

- `ParsoRadio/ViewModels/PlayerViewModel.swift`
- `ParsoRadio/Core/Models/MediaKind.swift`
- `ParsoRadio/Core/Models/MediaKind+Resolve.swift`
- `ParsoRadio/Core/Services/Playback/WholeItemController.swift`
- `ParsoRadio/Core/Services/Playback/RecentlyPlayedController.swift`
- `ParsoRadio/Core/Services/Playback/PlaylistPlaybackController.swift`
- `ParsoRadio/Core/Services/Playback/AudioPlayerService.swift`
- `ParsoRadio/Views/Player/NowPlayingSheet.swift`
- `ParsoRadio/Views/Player/PlayerControlBits.swift`
- `ParsoRadio/Views/Player/ScrubBar.swift`
- `ParsoRadio/Views/Player/Controls/MusicControls.swift`
- `ParsoRadio/Views/Player/Controls/SpokenControls.swift`
- `ParsoRadio/Views/Player/Controls/PodcastControls.swift`
- `ParsoRadio/Views/Player/Controls/AmbientControls.swift`
- `ParsoRadio/Views/Listen/ListenView.swift`
- `ParsoRadio/Views/Listen/LiveMusicDetailView.swift`
- `ParsoRadio/Core/Tests/NowPlayingSheetTests.swift`
- `ParsoRadio/Core/Tests/PlayerPerKindControlsTests.swift`
- `ParsoRadio/Core/Tests/PlayerSurfaceIntegrationTests.swift`
- `ParsoRadio/Core/Tests/AudioPlayerServiceContentModeTests.swift`

Current observed behavior:

- `NowPlayingSheet.controls` computes `let kind = playerVM.currentChannel?.mediaKind ?? .music`.
- `NowPlayingSheet.overflowMenu` and AirPlay toolbar use the same channel-only default.
- `BookForYouSection.playBook()` fetches tracks, then calls `playerVM.playAlbumTracks(tracks, title: entry.title)`.
- `WholeItemController.playAlbumTracks` sets `currentChannel = nil`, creates a temporary playlist, and does not set media kind.
- `PlaylistPlaybackController.loadPlaylist`, `RecentlyPlayedController.playRecentTrack`, `PlayerViewModel.playSingleTrack`, `playSequentialTracks`, `playSequentialItem`, `auditionTrack`, and `playSearchResult` also clear channel context without replacing it with an explicit surface kind.
- `AudioPlayerService.setContentMode` is called in `PlayerViewModel.load(channel:)`, but not consistently in direct/playlist contexts.
- `SpokenControls` still renders `ScrubRow(tint:showTimeLeftInWork:isLecture:)`.
- `ScrubRow` still renders elapsed time, remaining time, and "Book/Series ... left" when `timeLeftInBook` is available, but the active surface can bypass it.
- `ScrubBar` still uses a `Slider`, so scrubber control exists when spoken controls are selected.
- The repeated functional loss is caused by surface selection and weak surface contracts, not by an absence of reusable controls.

## Research Signal

- iOS audio apps need context-appropriate transport. All finite audio needs elapsed/remaining time and scrubbing. Music can still use track skip as its transport model, while spoken-word content additionally needs jog controls, speed, bookmarks, saved position, and work-level time left.
- The existing `MediaKind.behavior` table already encodes these differences. The missing piece is a first-class playback context that survives channel-less entry points.
- Current tests mostly validate `MediaKind` flags and local booleans. They do not force the production player sheet to resolve `.audiobook` for a book launched from `BookForYouSection`.

## Design

Add a typed playback context and make the player sheet depend on it.

```
PlayerViewModel
  @Published currentPlaybackContext: PlaybackContext?

PlaybackContext
  id: String
  origin:
    channel(channelId)
    playlist(playlistId)
    directItem(identifier)
    search(scope)
    madeForYou
    bookForYou
    liveMusic
    audition
  mediaKind: MediaKind
  title: String
  persistsResumePosition: Bool
  contentMode: AudioPlayerService.ContentMode

PlayerViewModel.activeMediaKind
  currentPlaybackContext?.mediaKind
  ?? currentChannel?.mediaKind
  ?? currentTrack?.mediaKind(in: currentChannel)
  ?? .music
```

Surface selection:

```
NowPlayingSheet
  let kind = playerVM.activeMediaKind

  music     -> MusicControls
  audiobook -> SpokenControls(isLecture: false)
  lecture   -> SpokenControls(isLecture: true)
  podcast   -> PodcastControls
  ambient   -> AmbientControls
```

Direct book launch flow:

```
BookForYouSection.playBook()
  -> fetch tracks
  -> playerVM.playAlbumTracks(tracks, title: entry.title, mediaKind: .audiobook, origin: .bookForYou)
  -> currentPlaybackContext.mediaKind = .audiobook
  -> audioPlayer.setContentMode(.spokenWord)
  -> NowPlayingSheet renders SpokenControls
```

Live Music launch flow:

```
LiveMusicSection.playAll()
  -> validated tracks
  -> playerVM.playAlbumTracks(tracks, title: entry.displayName, mediaKind: .music, origin: .liveMusic)
  -> currentPlaybackContext.mediaKind = .music
```

Time-control contract for finite non-ambient surfaces:

```
MusicControls / SpokenControls / PodcastControls
  ScrubRow
    ScrubBar Slider
    elapsed time
    Book/Series time left when available for audiobook/lecture
    -remaining time
```

Spoken transport contract:

```
SpokenControls
  jog -15
  play/pause
  jog +30
  Speed
  Chapters/Lectures
  Bookmark
  Sleep
```

## Data-Model Deltas

Playback context is required in memory and in persisted resume state:

- Add `PlaybackContext` model under `ParsoRadio/Core/Models/` or `ParsoRadio/Core/Services/Playback/`.
- Add `PlayerViewModel.currentPlaybackContext`.
- Add nullable/defaulted `media_kind_hint` to playlists.
- Add `UserDefaults "session.mediaKind"` to the session snapshot.
- Whole-book, Book For You, lecture, podcast, and live-music launches must set `mediaKindHint` at creation time.

Do not remove or change existing track/channel fields. Any schema change must be additive and defaulted.

## Implementation Steps

1. Add `PlaybackContext`.
   - Include `mediaKind`, `origin`, `title`, and computed `audioContentMode`.
   - Keep it lightweight and codable enough for session persistence.

2. Add `PlayerViewModel.activeMediaKind`.
   - Use `currentPlaybackContext` first.
   - Use `currentChannel?.mediaKind` second.
   - Use a strengthened `Track.mediaKind(in:)` third.
   - Default to `.music` only as the final fallback.

3. Set context in every playback entry point.
   - `load(channel:)`: `.channel(channel.id)`, `channel.mediaKind`.
   - `WholeItemController.playAlbumTracks`: new signature with `mediaKind` and `origin`.
   - `WholeItemController.playEntireCurrentItem`: infer from `activeMediaKind` or current track.
   - `PlaylistPlaybackController.loadPlaylist`: infer from playlist media-kind hint or dominant tracks.
   - `RecentlyPlayedController.playRecentTrack`: infer from track and persisted context if available.
   - `playSingleTrack`, `playSequentialTracks`, `playSequentialItem`, `auditionTrack`, `playSearchResult`: require or infer explicit context.
   - `BookForYouSection.playBook`: pass `.audiobook`.
   - `LiveMusicSection.playAll` and `LiveMusicDetailView.playAll/playFrom`: pass `.music`.
   - Direct search results: use the selected Search tab scope.
   - Mixed/manual playlists: use the current track's media kind unless a homogeneous playlist `mediaKindHint` is present.

4. Set `AudioPlayerService` content mode from context.
   - Whenever `currentPlaybackContext` is set, call `audioPlayer.setContentMode(.spokenWord)` for `.audiobook`, `.lecture`, `.podcast`; otherwise `.music`.
   - Keep channel load behavior unchanged but route it through the same helper.

5. Update `NowPlayingSheet`.
   - Replace every `playerVM.currentChannel?.mediaKind ?? .music` with `playerVM.activeMediaKind`.
   - Use `activeMediaKind` for controls, AirPlay visibility, and overflow menu.
   - Use context title as fallback artwork/title context when channel is nil.

6. Strengthen track inference.
   - Update `Track.mediaKind(in:)` so IA tracks with `parentIdentifier` and book/listened metadata can infer `.audiobook` when a context hint exists.
   - Do not guess every IA multi-part item is an audiobook; live music and albums can also be multi-part.

7. Make the time controls hard to remove.
   - Create `PlayerSurfaceSpec` or `PlayerControlsSpec` as a pure production model.
   - It should list required controls for each `MediaKind`.
   - Views render from the spec or tests assert against the exact spec the views use.
   - Every finite non-ambient spec must include scrub slider, elapsed time, and remaining time.
   - Audiobook and lecture specs must also include work-time-left.
   - Ambient is the only spec exempt from finite progress controls.

8. Enforce MP3-only before playback.
   - Any player entry point that expands, resolves, imports, downloads, or caches audio must reject non-MP3 tracks before calling `audioPlayer.play`.
   - Existing bundled ambient WAV files must be converted to MP3 or removed from the active playback path.

9. Add accessibility identifiers.
   - `player.scrub.slider`
   - `player.elapsed`
   - `player.remaining`
   - `player.work-time-left`
   - `player.surface.audiobook`
   - `player.surface.music`

## Testing Strategy

Add tests that exercise production paths:

- `PlaybackContextTests`
  - `BookForYou` path sets `.audiobook`.
  - `LiveMusic` path sets `.music`.
  - `load(channel:)` sets context equal to `channel.mediaKind`.
  - `playAlbumTracks(... mediaKind: .audiobook)` sets `AudioPlayerService.ContentMode.spokenWord`.

- `NowPlayingSurfaceResolverTests`
  - With `currentChannel == nil` and `currentPlaybackContext.mediaKind == .audiobook`, `activeMediaKind == .audiobook`.
  - With no context but podcast source, active kind resolves to `.podcast`.
  - With no context and no signal, active kind resolves to `.music`.

- `PlayerSurfaceSpecTests`
  - Music and Live Music specs include scrub slider, elapsed, and remaining.
  - Audiobook and lecture specs include scrub slider, elapsed, remaining, work-time-left, jog controls, speed, chapters, bookmark, sleep.
  - Podcast spec includes scrub, elapsed, remaining, jog, speed, episodes/bookmark/sleep as appropriate.
  - Ambient spec excludes finite progress controls.
  - All specs reject non-MP3 playable tracks before playback.

- Replace weak tests:
  - Refactor `NowPlayingSheetTests` and `PlayerSurfaceIntegrationTests` away from local booleans and into production resolver/spec assertions.

- UI smoke tests:
  - Launch a fake book-for-you entry with deterministic tracks.
  - Open player.
  - Assert `player.surface.audiobook`, `player.scrub.slider`, `player.elapsed`, `player.remaining`, and `player.work-time-left` exist.

Source guard:

- Add a test that fails if `NowPlayingSheet.swift` contains `currentChannel?.mediaKind ?? .music`.
- This is acceptable as an architectural ratchet because this exact pattern has caused repeated regressions.
- Add a test that fails if the shared audio selector admits Ogg, FLAC, M4A, AAC, Opus, WAV, SHN, or other non-MP3 formats.

## Settled Decisions

- Playlists persist nullable/defaulted `mediaKindHint`; homogeneous whole-item playlists set it at creation.
- Mixed/manual playlists use per-current-track media kind unless a homogeneous playlist hint is present.
- Live Music uses the music surface, but music still has elapsed, remaining, and scrubber controls.
- Direct search results get media kind from the selected Search tab scope.
