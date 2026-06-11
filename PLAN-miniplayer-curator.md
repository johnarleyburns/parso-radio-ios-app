# Plan: Add Miniplayer to Curator Screen

## Summary

Add a miniplayer bar to `CuratorChannelEditView` so the user always sees what's playing during curation, matching the behavior of `HomeView`, `MainMenuView`, and `ChannelListView`.

## Motivation

Currently the curator screen shows no indication of what track is playing. When the user presses play to audition a candidate, or when a channel is playing in the background before opening the curator, there is no visual cue. The miniplayer orients the user without requiring them to leave the curator.

## Approach

- Add a `.safeAreaInset(edge: .bottom)` modifier on the `NavigationStack` in `CuratorChannelEditView.body`
- Add a `private var miniPlayer: some View` computed property
- Follow the exact style of `HomeView`'s miniplayer (line 645 of `HomeView.swift`)

## Implementation details

### miniPlayer body

- Conditional on `playerVM.currentTrack != nil`
- `ArtworkThumbnail(track:size:40)` for artwork
- Track title (single line, semibold subheadline) + artist (single line, caption/secondary)
- Play/pause button calling `playerVM.togglePlayPause()`
- `.thinMaterial` background with `.separator` top border
- Tapping the miniplayer body calls `onDismiss()` — dismisses the curator sheet, returns user to the full player
- The existing `.onDisappear { playerVM.stopAudition() }` handles cleanup

### Performance

- The miniplayer reads `playerVM.currentTrack`, `playerVM.isPlaying` directly in `body`
- The curator view already recomputes `body` when `currentTrack` changes (via existing `.onReceive` → `curatorPlayback` → `@State` change)
- `$currentPosition` (4Hz) is NOT read by the miniplayer — no additional 4Hz recomputation
- Same pattern as `HomeView` and `MainMenuView`

### Files changed

- `ParsoRadio/Views/CuratedChannelsListView.swift` — one file, ~20 lines added

### Test implications

- No new unit tests needed
- Existing UI tests unaffected (miniplayer appears only when a track is loaded)
