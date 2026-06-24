# Design — per-problem anatomy

## A. Music For You header / layout / always-on spinner

- **Problem**: shelf header has a `sparkles` icon + custom font and only renders
  when loaded; idle state renders a 0-height row so nothing shows on launch.
- **Current behavior**: `MadeForYouSection.swift` header gated on
  `if case .loaded(... ), !tracks.isEmpty`; `.idle` → `Color.clear.frame(height: 0)`.
- **Research signal**: peer sections (`HomeSections.swift`, `ListenView.swift`)
  use a plain `Text("…")` section header, always present.
- **Design**:
  ```
  Section {
    .idle/.loading  → spinner row "Finding music for you…"
    .loaded(tracks) → horizontal JumpBackInCard scroller   (unchanged layout)
    .loaded(empty)  → "No music picks right now."
    .empty/.failed  → message + Retry (header still shows)
  } header: { Text("Music For You") }     // always, no icon, default font
  ```
- **Data-model deltas**: none.
- **Implementation steps**: rewrite the `header`/`footer`/`switch` so the header
  is unconditional, idle and loading both render the spinner, drop the
  `sparkles`/gradient/headline styling.
- **Testing**: `RegressionContractSourceTests.testMadeForYouSectionDoesNotGateOnHiddenState`
  must still pass (no `if showSection`). File name stays `MadeForYouSection.swift`.

## B. Music-only results

- **Problem**: shelf shows LibriVox / lectures / podcasts.
- **Current behavior**:
  - `MadeForYouShelfStore.fetchColdStartPicks()` queries
    `collection:librivoxaudio` (audiobooks).
  - personalized path calls `RecommendationsController.fetchMixedRecommendations()`
    which unions `music` **and** `spoken` profile queries.
- **Design / Implementation steps**:
  - `RecommendationsController.fetchMixedRecommendations(musicOnly: Bool = false)`:
    when `musicOnly`, skip `spokenProfile` queries and the spoken fallback.
    Default `false` preserves all existing callers/tests.
  - `MadeForYouShelfStore`: call `fetchMixedRecommendations(musicOnly: true)`;
    remove the `collection:librivoxaudio` cold query; add a defensive filter
    dropping `source == "podcast" || source == "oxford_lectures"`.
- **Data-model deltas**: none.
- **Testing**: `RecommendationsControllerTests` unaffected (defaulted param).

## C. Reorder — Book directly below Music

- **Current order** (`ListenView.body`): Top, MadeForYou, ExploreTypeRow,
  FeaturedToday, BookForYou, LiveMusic, Browse.
- **New order**: Top, **MadeForYou, BookForYou**, ExploreTypeRow, FeaturedToday,
  LiveMusic, Browse.

## D. Music + audiobook scrub / elapsed / remaining

- **Problem**: music surface has no scrub row; audiobook reported missing too.
- **Current behavior**: `MusicControls` omits `ScrubRow`. `SpokenControls`
  (audiobook + lecture) already includes `ScrubRow(... showTimeLeftInWork: true)`.
- **Design**: add `ScrubRow(tint: tint)` as the first child of `MusicControls`'s
  `VStack`, mirroring `PodcastControls`. Leave `SpokenControls` intact.
- **Decision**: do not touch `MediaKind.behavior` (see overview).
- **Testing**: add `RegressionContractSourceTests.testMusicControlsRendersScrubRow`
  asserting `MusicControls.swift` contains `ScrubRow`. `MediaKindTests` /
  `PlayerPerKindControlsTests` remain unchanged and green.

## E. Overflow Download (all kinds except ambient)

- **Current behavior**: `overflowMenu` has Add-to-playlist / Share / archive.org /
  book-skip — no download.
- **Design**: in `overflowMenu`, when `kind != .ambient` and the current track has
  a `downloadURL`, show one of:
  - downloading → disabled `Label("Downloading…", systemImage: "arrow.down.circle")`
  - downloaded (`localFilePath != nil`) → `Button("Remove Download")` →
    `offlineService.removeOffline(track:)`
  - else → `Button("Download")` → `offlineService.makeOffline(track:)`
  Reuse `offlineService.trackProgress[track.id]` for the in-flight state and
  observe `offlineService.singleTrackVersion` so the row refreshes.
- **Wiring**: `NowPlayingSheet` gains `@EnvironmentObject var offlineService`.
  Inject `.environmentObject(deps.offlineService / offlineService)` at the easy
  presentation sites (ListenView ×2, MiniPlayer, KidsHomeView); rely on
  environment inheritance for ChannelBrowseList / FavoritesScreen.
- **Ambient exclusion**: gated by `kind != .ambient`; ambient tracks also have
  `downloadURL == nil`, so they are excluded twice over.

## Open questions

- None blocking. Music-only cold start depends on IA network at first launch; the
  always-on header + spinner + Retry guarantees the section is never hidden.
