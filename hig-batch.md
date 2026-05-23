# HIG Batch — design

Implement HIG recommendations #1–5 (the drill-down menu is tracked
separately and NOT part of this batch).

## 1. Dynamic Type on the track box
**Problem:** the track box uses fixed `.system(size: 19/14)` plus a
`.dynamicTypeSize(.medium ... .accessibility2)` clamp — so text doesn't
actually scale with the user's setting; it just hard-stops.
**Design:** replace the two fixed sizes with `@ScaledMetric` so they grow/
shrink relative to a text style, keeping the layout clamp:
- `@ScaledMetric(relativeTo: .title3) var titleSize = 19`  (channel/playlist
  title + track title)
- `@ScaledMetric(relativeTo: .subheadline) var detailSize = 14` (artist,
  part, dates, elapsed/remaining, loading message, error/idle text)
Keep `ClickWheel.iconSize` fixed (it's a control glyph in a fixed-geometry
wheel, not body text — HIG doesn't require control chrome to scale). Menu /
sheets already use semantic styles (.body/.caption/.subheadline) and scale.

## 2. Light/Dark mode + contrast
**Problem:** the device body is a hardcoded slate-blue
`Color(red:0.290,0.333,0.408)` regardless of appearance; white track text
over a light album cover can fall below 4.5:1.
**Design:**
- Device body becomes a dynamic `UIColor` (dark slate in Dark Mode, a
  slightly lighter slate in Light Mode) so the shell adapts.
- Strengthen the bottom scrim (0.75 → 0.82) and add a subtle text shadow to
  the track title + metadata so white text always clears contrast over light
  artwork.

## 3. iPad layout
**Problem:** the single centered iPod column stretches huge on a regular-
width iPad (oversized wheel, wasted space).
**Design:** read `@Environment(\.horizontalSizeClass)`. In `.regular`, cap
the iPod shell to a sensible max width (~480 pt) and center it, so it stays
iPod-proportioned instead of filling a 12.9" display. Low-risk; no behavioral
change on iPhone (`.compact`). (A full sidebar is out of scope for this batch.)

## 4. Wheel-gesture discoverability (onboarding)
**Problem:** double-tap-skip, press-and-hold-scrub, centre=Track Info, and
menu double-tap=Main Menu are invisible — HIG wants non-standard gestures to
be discoverable.
**Design:** a `WheelHelpView` overlay listing the wheel actions. Shown once
automatically on first launch (UserDefaults `didShowWheelHelp`), and re-
openable any time from a "How the wheel works" row in About. Dismissible,
respects Reduce Motion / Dynamic Type.

## 5. Reduce Transparency
**Problem:** the menu mini-player uses `.thinMaterial`; HIG says honor
`accessibilityReduceTransparency` with an opaque fallback.
**Design:** read `@Environment(\.accessibilityReduceTransparency)`; the
mini-player background becomes opaque `Color(.systemBackground)` when reduced,
else `.thinMaterial`. Audit other material uses (loading overlay is a plain
black scrim — fine; sheets are system List — fine).

## Validation
swiftc -parse all changed files; no IA queries change (no curl). Update/
add tests where logic is testable (Dynamic Type / colors / Reduce
Transparency are view-only — covered by parse + manual). Push as one batch,
watch CI, iterate to green.
