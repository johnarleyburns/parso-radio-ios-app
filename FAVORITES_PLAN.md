# Favorites System — Implementation Specification

## Overview

The app plays mixed media: music tracks, audiobooks (multi-chapter), podcasts (multi-episode), and lectures (single talks or series). There is **one universal "favorite" action** (a heart button) shown on all playable content, but favorites are **stored and displayed segmented by content type**, because "favorite" means different things for different media:

- For music: "I want to replay this, including on shuffle."
- For long-form content (audiobooks, podcasts, lectures): "Save this work so I can return to it" — a bookmark/save model, not a shuffle-pool model.

The user never chooses a category when favoriting. The content type determines where the favorite lands.

## Content Type Taxonomy

Every playable item must have a resolvable `contentType`:

| contentType | Unit the user taps heart on | Unit that gets favorited |
|---|---|---|
| `musicTrack` | track | the track itself |
| `audiobook` | chapter (a track within a book) OR the book detail page | the **book** (parent work), with the chapter stored as a resume bookmark |
| `podcastEpisode` | episode | the episode |
| `lecture` | lecture/talk | the lecture |

Rule: for `audiobook`, favoriting is always promoted to the parent work. Favoriting chapter 12 of a book favorites the book and records `{bookID, chapterIndex, timestamp}` as the bookmark. There is no such thing as a favorited chapter existing independently of its book.

Albums are NOT a separate favorite type. Favorited music tracks can be *grouped by album* in the UI, but there is no `favoriteAlbum` entity. (If a future "favorite whole album" gesture is added, implement it as batch-favoriting the album's tracks plus an `albumGrouped: true` display hint — do not create a new entity type.)

## Data Model

```swift
enum FavoriteKind: String, Codable {
    case track       // musicTrack
    case book        // audiobook parent work
    case episode     // podcastEpisode
    case lecture
}

struct Favorite: Codable, Identifiable {
    let id: String              // stable ID, see ID rules below
    let kind: FavoriteKind
    let dateAdded: Date

    // Display metadata (denormalized so the list renders offline
    // without re-fetching Internet Archive):
    let title: String
    let creator: String?        // artist / author / speaker
    let artworkURL: URL?
    let sourceIdentifier: String  // IA identifier or channel/source ID

    // Long-form only (book/episode/lecture):
    var resumePoint: ResumePoint?
}

struct ResumePoint: Codable {
    var chapterIndex: Int?      // nil for single-file works
    var positionSeconds: Double
    var updatedAt: Date
}
```

### ID rules
- `track`: `"\(iaIdentifier)/\(fileName)"` — unique per file within an Internet Archive item.
- `book`: the parent work's identifier (IA item identifier or LibriVox book ID). Never the chapter file.
- `episode` / `lecture`: the individual file or episode GUID if available, else `identifier/fileName`.

Favoriting is idempotent: favoriting an already-favorited item is a no-op (or updates `resumePoint` for long-form — see below). Unfavoriting removes the entity entirely, including its resume point.

## Heart Button Behavior

The heart button appears on: now-playing screen, track rows, book/episode/lecture detail pages.

**State resolution (what "filled heart" means):**
- On a music track row or its now-playing screen: filled iff that track ID is favorited.
- On an audiobook chapter row or its now-playing screen: filled iff the **parent book** is favorited. All chapters of a favorited book show a filled heart.
- On a book detail page: filled iff the book is favorited.
- On podcast episode / lecture: filled iff that episode/lecture ID is favorited.

**Tap behavior:**
- `musicTrack`: toggle favorite on the track.
- `audiobook` (tapped from a chapter or now-playing):
  - If book not favorited → favorite the book; set `resumePoint` to the current chapter + playback position (or chapter start if not playing).
  - If book already favorited → unfavorite the book (remove it and its resume point). Do NOT silently update the bookmark on tap; bookmark updates happen automatically during playback (below).
- `podcastEpisode` / `lecture`: toggle favorite on that item; capture current playback position into `resumePoint` when favoriting mid-playback.

**Automatic resume-point updates:** for any favorited long-form item, update `resumePoint` on pause, on app background, on chapter change, and every 30 seconds during playback. This is independent of the heart button.

## Favorites Screen

A single "Favorites" destination, internally segmented. Sections render in this order, hiding empty sections:

1. **Songs** (`kind == .track`)
   - Default sort: dateAdded descending. Secondary view toggle: group by album (group key = album title + artist; tracks without album metadata go in a "Singles" group).
   - Row tap: play the track. Section header includes "Play" and "Shuffle" actions scoped to favorited songs only.
2. **Books** (`kind == .book`)
   - Card/row shows title, author, artwork, and a progress affordance: "Resume — Ch. {chapterIndex + 1}" derived from `resumePoint`. Tap = resume playback at the resume point. Secondary tap target (chevron / long-press) opens the book detail page.
3. **Podcasts** (`kind == .episode`)
   - Row shows episode title, show name, and resume position if partially played. Tap = resume.
4. **Lectures** (`kind == .lecture`) — same pattern as Podcasts.

If total favorites ≤ 8 across all kinds, a flat combined list grouped with small section labels is acceptable; otherwise use full sections (optionally with a segmented control / tab strip: All · Songs · Books · Podcasts · Lectures).

## Playback Rules

- **Shuffle in Favorites must only ever include `kind == .track` items.** Long-form favorites are never injected into a music shuffle queue.
- "Play" on the Songs section enqueues favorited songs in current sort order.
- Resuming a Book/Podcast/Lecture builds its normal sequential queue (remaining chapters/episodes of that work), starting at `resumePoint`.
- Favorites is system-managed: users cannot reorder it or insert arbitrary items. Mixed-media listening is served by **user-created playlists**, which may freely contain any content type and are a separate feature from favorites.

## Persistence

- Store favorites locally (e.g., a JSON file in Application Support, or SwiftData/Core Data — match whatever the app already uses for channels). Single source of truth; UI observes it (e.g., an `@Observable FavoritesStore`).
- Writes must be atomic and immediate on every mutation (favorite, unfavorite, resume-point update). No batching that can lose state on force-quit.
- Denormalized metadata means the Favorites screen must render fully offline. Artwork may lazy-load; never block the list on a network call.

## Edge Cases

- **Favoriting from a mixed channel/playlist:** resolve `contentType` from the item's own metadata, not from the channel it was played in. An audiobook chapter inside a user playlist still promotes to favoriting the book.
- **Unknown content type:** default to `track` behavior (favorite the individual file). Never crash or hide the heart.
- **Source item removed/unavailable upstream (IA item dark or missing):** keep the favorite, render it with a "currently unavailable" state on playback failure. Do not auto-delete user favorites.
- **Same work appearing in multiple channels:** the ID rules above must dedupe — favoriting it from either place yields one Favorite entity.
- **Migration:** if any legacy single-list favorites exist, migrate each entry by resolving its content type with the rules above; audiobook chapter entries collapse into one book favorite keeping the earliest `dateAdded` and the most recent position as `resumePoint`.

## Acceptance Criteria

1. Tapping the heart on a music track adds/removes exactly that track under Songs.
2. Tapping the heart on any audiobook chapter adds/removes the **book** under Books; all chapters of that book then show a filled heart.
3. A favorited book's row resumes playback at the stored chapter/position with a single tap, and that position updates automatically as the user listens.
4. Shuffle within Favorites never plays an audiobook chapter, podcast episode, or lecture.
5. The Favorites screen renders correctly with no network connection.
6. Favoriting the same item twice (from different screens or channels) produces one entry.
7. Unfavoriting a book removes its bookmark; re-favoriting later starts a fresh resume point.
