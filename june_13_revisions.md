# June 13 Revisions — Fix Plan

## 1-9, 17: Player View Changes (NowPlayingSheet.swift, TransportControls.swift, ScrubBar.swift)

### Current layout (single ScrollView VStack):
```
  artwork
  trackInfo
  TransportControls (<<, >, >>)
  globalControls (heart, share, AirPlay, archive.org)
  behaviorSpecificControls (ScrubBar, shuffle, repeat, speed, sleep timer...)
```

### Target layout (controls anchored to bottom; artwork + track info in scrollable area above):
```
  [ScrollView]
    artwork (260×260)
    trackInfo (title, artist, composer)
  [/ScrollView]
  Spacer()
  [heart]  elapsed  [========progress bar========]  remaining  [share]
                    [<<]  [>]  [>>]
               [shuffle]       [repeat]
          [archive.org] [AirPlay] [+playlist]
```

### Detailed changes:
1. **ScrubBar moved above TransportControls** — reorder in NowPlayingSheet
2. **Left/right arrows closer to center** — reduce horizontal padding in TransportControls
3. **Elapsed time above left side of progress bar** — build new progress bar component
4. **Remaining time above right side of progress bar** — compute `duration - currentPosition`
5. **Favorites icon above elapsed time** — VStack with heart above elapsed
6. **Share icon above remaining time** — VStack with share above remaining
7. **Shuffle left-justified below <<** — placed in TransportControls area
8. **Repeat right-justified below >>** — placed in TransportControls area
9. **archive.org, AirPlay, +playlist centered below > play button** — icon-only buttons
17. **Controls anchored to bottom** — use VStack with Spacer() instead of single ScrollView

## 10: Long-press channel → curate popup

**File**: `ParsoRadio/Views/Listen/ListenView.swift`
- Add `.contextMenu {}` to channel rows in the ListenView
- For "Curated" channels: include "Curate" button that opens CuratorChannelEditView
- For user-created channels: include "Curate", "Rename", "Delete" buttons
- For all channels: include "Channel Info" button

## 11: "+" icon on Books row

**File**: `ParsoRadio/Views/Listen/ListenView.swift`
- Add "+" button to Books section header
- Opens a sheet for creating a new curated books channel (NewChannelSheet with contentType=.spokenWord)

## 12: "+" icon on Podcast line

**File**: `ParsoRadio/Views/Listen/ListenView.swift`
- Add "+" button to Podcasts section header
- Opens PodcastAddView (already exists)

## 13: Music category missing (CRITICAL)

**File**: `ParsoRadio/Views/Listen/ListenView.swift`
- **Root cause**: `dedicated` set contains `"Curated"` which filters out all music channels
  (Classical Guitar, String Quartet, etc., all have `category == "Curated"` and `mediaKind == .music`)
- **Fix**: Remove `"Curated"` from the `dedicated` filter set
- Result: Music section now shows all 9 curated music channels

## 14: Live Music single card

**File**: `ParsoRadio/Views/Listen/ListenView.swift`
- Replace `LiveMusicSection` that shows 5 "Curated" channels with a single card
- Fetch entry from `LiveMusicOnThisDayService`
- Show artwork thumbnail, artist name, date, venue, download count
- Single tappable card that starts playback of the live recording

## 15: Downloads deletion via native HIG

**Files**: 
- `ParsoRadio/Views/Library/LibraryView.swift` — add "Clear All Downloads" button at top + swipe-to-delete
- `ParsoRadio/Views/SettingsView.swift` — remove "Delete All Downloaded Tracks" and "Downloads by Playlist" sections

## 16: Supporter badge on Listen line

**File**: `ParsoRadio/Views/Listen/ListenView.swift`
- Show supporter badge (`seal.fill`) right-justified on the navigation title bar
- Same font size as "Listen" navigation title
- Only shown when user is a supporter and badge is not hidden

## 13: Remaining time fix

**File**: `ParsoRadio/Views/Player/ScrubBar.swift`
- Change right time label from total duration to remaining time (duration - currentPosition)
