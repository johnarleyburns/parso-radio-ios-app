# Settled Decisions

These decisions are settled for implementation. Do not leave them as open questions in the plan and do not re-litigate them during later phases unless the developer explicitly changes the requirement.

## D-001: Made For You Visibility Contract

"Made for You" must always be visible on Listen once the onboarding sheet has been dismissed, including when the user skipped onboarding. Show one of four explicit states: loading, personalized tracks, cold-start tracks, or retry/empty. Never hide the section solely because the network or recommendation query returned no tracks.

## D-002: Existing-User Backfill

Existing users with play history but no taste profile must get an automatic one-time backfill. On first launch after this fix, derive taste terms and seen identifiers from `track_play_history` joined to `tracks`, capped to recent history, and mark a versioned backfill key only after success.

## D-003: Live Music Candidate Requirements

Before a Live Music candidate can be published, it must have a non-empty display name, a date matching today's `MM-dd`, at least one playable MP3 file selected by the global MP3-only audio policy, and a known artwork fallback if `services/img` is a placeholder. If metadata title is missing, synthesize the display name from creator plus venue/date; do not publish a creator-only or date-less card. If any requirement fails, skip the candidate and try another.

## D-004: Global Audio Format Policy

All audio playback paths must accept MP3 only: MP3 Layer 3, VBR MP3, and IA MP3 derivatives such as `VBR MP3`, `128Kbps MP3`, `64Kbps MP3`, `MP3`, or files with a `.mp3` extension. Reject Ogg, FLAC, M4A, AAC, Opus, WAV, SHN, video containers, metadata-only files, and every other non-MP3 format. This applies to Internet Archive, podcasts/RSS, FMA, local import, downloads/cache, Live Music, Book For You, Made For You, playlists, search, and bundled ambient assets. Existing bundled WAV ambient files must be converted to MP3 or removed from active playback paths.

## D-005: Playback Context Persistence

Use an in-memory `PlaybackContext` immediately for all active playback, and also persist enough media-kind context for relaunch/resume. Add a nullable/defaulted `mediaKindHint` for playlists plus `session.mediaKind` in the session snapshot. Whole-book, Book For You, lecture, podcast, and live-music launches must set the hint at creation time.

## D-006: Surface Defaults For Unknown Direct Tracks

Use the initiating search scope or explicit caller context. Only fall back to `.music` after checking `PlaybackContext`, `session.mediaKind`, playlist `mediaKindHint`, `Track.source`, `Track.parentIdentifier`, and current playlist context.

## D-007: Agent Quality Gate

Update `AGENTS.md` with a project-specific Regression Contract that prevents "implemented" claims without exact affected files, production-contract tests, verification commands/results, and UI smoke evidence for Listen/player changes. Coding agents must stop at PR creation for these high-risk phases unless a human explicitly asks them to merge to `main`.

## D-008: Time And Scrubber Controls

Every finite non-ambient audio surface must show elapsed time, remaining time, and a scrubber/slider. Audiobook and lecture surfaces must also show book/series time left when the current item has parts. Ambient loops are the only surface exempt from finite progress controls.

## D-009: Live Music Cache And Empty State

Live Music daily cache keys must use full `yyyy-MM-dd`, while candidate search still matches today's `MM-dd`. If no validated MP3 candidate exists, show the visible empty/error state with retry; do not hide the section and do not publish an invalid fallback.

## D-010: Made For You Cache And Cold Start

Made For You must use a small daily cache in Phase 1 so the shelf remains stable within a day. Cold-start content must include both music and audiobooks, with explicit media-kind context on every item tap.
