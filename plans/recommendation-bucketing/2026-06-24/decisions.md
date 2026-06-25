# Decisions

1. **Profile migration strategy** → *Clean rebuild, preserve onboarding.*
   Rebuild both taste buckets from authoritative `track_play_history`
   (channel-aware). Preserve onboarding/favorite emphasis via a snapshot →
   rebuild → residual-restore step, excluding terms that the rebuild proves are
   audiobook-origin (present in the spoken bucket). Going forward, persist
   onboarding chip IDs so future rebuilds replay onboarding exactly.

2. **Books collection scope** → *`librivoxaudio` only.*
   All books query classes (exploit/explore/serendipity/fallback) scope to
   `collection:librivoxaudio`. `audio_bookspoetry` is intentionally excluded.

3. **Plan docs first** → *Yes.* Authored under
   `plans/recommendation-bucketing/2026-06-24/` before code.

## Known feasibility caveat (recorded)

Onboarding selections are NOT persisted today (`OnboardingTasteView.selectedIDs`
is transient `@State`; only `hasCompletedOnboarding` is stored). A literal
"replay onboarding" is impossible for already-onboarded users. Hence the
snapshot/residual approach for the migration, plus persisting
`onboardingChipIDs` for future runs.
