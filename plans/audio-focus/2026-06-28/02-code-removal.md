# 02 — Code Removal & Spoken-Word-Safe Replacement

Every removal below is grounded in exact files/lines from the 2026-06-28 audit. Removals are **non-destructive to user data**: legacy music rows in SQLite are hidden/ignored, never deleted.

> After any `.swift`/resource add/remove: run `xcodegen generate` (Common Pitfall: files not auto-discovered).

---

## P1 — Music recommendation surfaces

### Problem / Current Behavior
"Music For You" shelf + a full music recommendation/taste path runs alongside Books for You.

### Files & lines
- **Delete** `ParsoRadio/Views/Listen/MadeForYouSection.swift` (entire music shelf; header `Text("Music For You")` :81, spinner "Finding music for you…" :21).
- **Remove** `MadeForYouSection()` mount in `ParsoRadio/Views/Listen/ListenView.swift:22`.
- `ParsoRadio/Core/Services/Playback/MadeForYouShelfStore.swift`: remove `Shelf.music` (:40), default `.music` (:54), music branch in `filtered()` (:154–161, `$0.inferredMediaKind == .music` :157), music cold-start query (:166–171), music snapshot keys (:332–339 `madeForYou.snapshot.music`), music cache day key (:370–378). Collapse store to books-only (or hardcode `shelf == .books`).
- `ParsoRadio/Core/Services/Playback/RecommendationsController.swift`: remove `musicScope`/`musicOnly` path (:15–33, :25 `RecommendationScope.music`); keep books path only.
- `ParsoRadio/Core/Services/API/RecommendationQueryBuilder.swift`: remove `RecommendationScope.music` case (:19–37, default-to-`.music` overload :42–50).
- `ParsoRadio/Core/Services/Storage/TasteProfileStore.swift`: `bucketFor()` (:178–184) drop `.music`/`.ambient`→"music" bucket; keep only "spoken". Update `resolvedKind` (:189–196). Backfill version bump (`MadeForYouShelfStore.swift:50–51`, currently v4) → v5 to clear stale music-bucket data.
- `ParsoRadio/Resources/ia_queries.json`: delete `music-for-you` entry (:2–8). Keep `books-for-you` + 21 `lv-*`.
- `ParsoRadio/Core/Models/Channel.swift`: remove `music-for-you` channel (:148–154) and the mixed `for-you` channel (:139–145) (resolves to `.music`). Keep `books-for-you` (:155–162).
- **Delete asset** `ParsoRadio/Resources/Assets.xcassets/music-for-you.imageset/`.
- `ParsoRadio/Core/Models/PlaybackContext.swift`: remove/repurpose `Origin.madeForYou` (:9) and `Origin.liveMusic` (:11).
- Tests to update/remove: `ChannelTests.swift:29`, `MediaKindTests.swift:9`, `PlaybackContextTests.swift:41–49`, `RegressionContractSourceTests.swift:34–39,80–90`, `BooksForYouShelfStoreTests.swift:26–50`, `PlaybackReliabilityTests.swift:221–226`, `ImageDisplayUITests.swift:128`.

### Spoken-word-safe replacement
Recommendations only ever query `collection:librivoxaudio`. `RecentWork`/Jump-Back-In legacy music rows fall through to the hidden path (see P4).

---

## P2 — IA music collections + FMA

### IA "Internet Archive Collections"
- **Delete** `ParsoRadio/Resources/default_collections.json` (18 collections).
- **Delete** `ParsoRadio/Core/Services/IACollectionStore.swift` (loader :129–136, `asChannel()` category "Curated Music" :30–41). Remove DI in `AppDependencies.swift:18,36,53`, `ParsoRadioApp.swift:31`.
- **Delete** `ParsoRadio/Views/AddCollectionView.swift`.
- `ParsoRadio/Views/Listen/ChannelBrowseList.swift`: remove `iaCollectionStore` (:11), `kind == .music` gating (:37,68,117 "Add collection"), swipe-remove (:102–105).
- `ParsoRadio/Views/Listen/HomeSections.swift:197,200` and `ParsoRadio/Views/Listen/ListenView.swift:90`: drop `IACollectionStore.shared.channels` from Featured/hero pools.
- `ParsoRadio/Views/ChannelInfoView.swift:48`: remove collection-info lookup.
- `ParsoRadio/Core/Models/LibrarySectioning.swift:12`: remove the `.music` "Internet Archive Collections" row.

### FMA
- **Delete** `ParsoRadio/Core/Services/API/FMAService.swift`.
- Remove injection: `AppDependencies.swift:9,28,45`; `ParsoRadioApp.swift:23`; `PlayerViewModel.swift:71,192,206,411`.
- Remove fetch calls: `PlayerViewModel.swift:623,638` (Tag/Composer parallel IA+FMA fetch → IA-only or removed with their music channels).
- Source labels: `Utilities/SharedViews.swift:56,70` ("Free Music Archive"), `Views/ChannelInfoView.swift:123`.
- Tests/helpers/fixtures: `TestChannels.swift:1–19` (fma*TestChannel), `PlayerViewModelTests.swift:734–736` (`makeFMATrack`), `PlaybackReliabilityTests.swift:39–40`, `ChannelTests.swift:56–61` (`testNoContemporaryOrFMAChannelsRemain` — keep/strengthen as a guard), plus all `FMAService()` injections (see audit list). Comments referencing FMA in `Channel.swift:23,87,269`.

---

## P3 — Search + UI language

- `ParsoRadio/ViewModels/SearchViewModel.swift`: `SearchScope` (:28–47) drop `music`,`albums`; keep `audiobooks`,`podcasts` (+ lectures per D-2). Default scope (:50) → `.audiobooks`. `ItemKind` (:20) drop `track`,`album` (or keep `book` only). `mediaKind(forCollection:)` (:163–165) never returns `.music`.
- `ParsoRadio/Views/SearchView.swift`: scope picker (:52–61), `handleTap` track path (:316–327), `searchFavoriteMediaKind` album→.music (:329–337), `kindIcon`/`kindLabel` (:368–383) → book/episode only. Placeholder (:31) and helper (:175) copy.
- `ParsoRadio/ViewModels/PlayerViewModel.swift:1790–1791`: `playSearchResult(mediaKind:)` default must not be `.music`.
- `ParsoRadio/Views/Search/ItemDetailView.swift:25–29`: noun mapping is already book/album-aware; force book/series wording, `favoriteMediaKind` never `.music`.
- Welcome card `HomeSections.swift:46`, library tab icon `RootTabView.swift:17` (`music.note.list`→`books.vertical`), generic "tracks" copy per D-3.

---

## P4 — Player / runtime media model

### Problem
`MediaKind.music` / `ContentType.music` and many `.music` fallbacks drive a music player surface and music-only transport.

### Files & lines
- `ParsoRadio/Core/Models/MediaKind.swift`: `case music` (:4) + its `PlaybackBehavior` (:28–66). Decision D-4: **keep the raw value for legacy decode but make it unreachable for new content**, OR delete the case. Plan language is "remove from behavior".
- `ParsoRadio/Core/Models/Channel.swift`: `ContentType.music` (:3–7); change init default `contentType = .music` (:45) to `.spokenWord`.
- `ParsoRadio/Core/Models/MediaKind+Resolve.swift`: the three `.music` fallbacks (:12 Channel, :30 `mediaKind(in:)`, :48 `inferredMediaKind`) → return an "unsupported/hidden" outcome so legacy music items don't surface. Keep audiobook/lecture/podcast/ambient resolution.
- `ParsoRadio/Views/Player/NowPlayingSheet.swift`: controls switch `.music → MusicControls` (:223); add-to-playlist `kind == .music` gate (:244); `surfaceAccessibilityID` default `.music` (:18–24).
- **Delete** `ParsoRadio/Views/Player/Controls/MusicControls.swift` and `ParsoRadio/Views/Player/AlbumTracksButton.swift`.
- `ParsoRadio/Views/Player/PlayerControlBits.swift`: `ShuffleButton` (:63–72), `RepeatButton` (:74–83) — remove (music-only).
- `ParsoRadio/ViewModels/PlayerViewModel.swift`: `activeMediaKind` `.music` fallback (:123); `advanceToNext` `randomAlbumTrack` for music (:935–943); shuffle/repeat (`shuffleMode` :18, toggleShuffle :1695–1703, toggleRepeat :1734–1738); `setContentMode(... .music)` (:531).
- `ParsoRadio/Core/Models/PlayerSurfaceSpec.swift:18–31` music spec; `AudioPlayerService.swift:29,600` default/remote `.music`.
- `ParsoRadio/Core/Services/Playback/RecentlyPlayedController.swift`: `resumeMusicAlbum` (:88–120), `.music` dispatch (:65), hardcoded `.music` (:118). Update collapse rules to audiobook/lecture/podcast/ambient only.
- `ParsoRadio/Core/Services/Storage/DatabaseService.swift`: `fetchRecentlyPlayedWorks` (:1045–1080) — legacy `media_kind == "music"` rows return nil/unsupported and are excluded from shelves.
- `ParsoRadio/Core/Models/Favorite.swift:11,63,72`: `.music,.ambient` grouped — keep ambient, drop music.

### Ambient (D-1)
If kept: ensure ambient is never labeled "music". `ambient-yellowstone` currently has no `contentType` so it resolves via `category == "Ambient"` — verify it still resolves to `.ambient` after the init default flips to `.spokenWord`. Ambient grouping with music in `Favorite.swift`/`TasteProfileStore` must be re-pointed to ambient-only handling.

---

## P5 / P6 / P7
Rights audit + podcast licensing → `03-rights-privacy.md`. Copy/manifest/docs → `03-rights-privacy.md` + P6 list there. Verification → `04-verification-rollout.md`.

## Open Questions
- **D-4:** Delete `MediaKind.music`/`ContentType.music` cases vs keep raw values for legacy decode only. Deleting forces an exhaustive compiler-checked sweep (safer long-term) but breaks legacy `Codable` decode of stored music rows — which we must still *read* to hide them. **Recommended: keep the raw `case music` for decode, route it to a hidden/unsupported path, and add a guard test that no *new* content is created as `.music`.**
