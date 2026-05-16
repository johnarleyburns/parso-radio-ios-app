# iPod UI Revamp Plan (adapted to this codebase)

The original recommendation referenced `NowPlayingView.swift`,
`ClickWheelView.swift`, `PlayerProgressView.swift`, and a color asset
catalog. **This project has none of those.** Everything lives in a single
file: `ParsoRadio/Views/iPodView.swift`. This plan maps every step to the
actual symbols in that file.

## Symbol map (recommendation → this codebase)

| Recommendation term | Actual symbol in `iPodView.swift` |
|---|---|
| `NowPlayingCard()` | `private var screenPanel` (ZStack, `.clipShape(RoundedRectangle(cornerRadius: 20))`) |
| Album art + overlay | `private var artworkBackground` (Rectangle + `.overlay` image + `.clipped()`) and the separate dark `LinearGradient` layer in `screenPanel` |
| Song/artist/genre text | `private func trackMetadataStack(track:)`, plus the channel-name `HStack` at the top of `screenPanel` |
| Attribution pill (CC/Archive.org) | `licenseRow(_:source:)` + `screenBadge(_:)` — currently rendered inside `trackMetadataStack` |
| `ClickWheelView()` | `struct ClickWheel` (bottom of the same file) |
| `PlayerProgressView` / slider | `private var scrubberRow` (`Slider` + time `HStack`) |
| `Color("iPodSlate")` | inline `Color(red: 0.290, green: 0.333, blue: 0.408)` in `body` |
| Color asset catalog | none — colors are inline literals; add semantic colors in `ParsoRadio/Resources/Assets.xcassets` if we want named colors |

Note: the body is `GeometryReader → ZStack → VStack { screenPanel; Spacer; ClickWheel; Spacer }`. Top margin was already reduced to ~0 (`.ignoresSafeArea(edges: .top)`, no `.padding(.top)`).

## Steps (mapped, not yet implemented)

1. **Layout grounding** — `screenPanel` and `ClickWheel` are siblings in the
   VStack with two `Spacer()`s. To make them feel like one object: reduce the
   inter-element gap, add a hairline/shadow separator between panel and wheel.
   Files: `body` VStack in `iPodView.swift`.

2. **Album-art legibility** — the dark gradient already exists as a separate
   `LinearGradient([.clear, .black.opacity(0.75)])` layer in `screenPanel`.
   Increase to `0.85` at the bottom and ensure all of `trackMetadataStack`
   sits within it. Already structurally correct after the `artworkBackground`
   Rectangle+overlay+clipped fix.

3. **Typography (SF Pro / HIG)** — in `trackMetadataStack`:
   - channel/genre label → `.caption2`, `.white.opacity(0.7)`, slight tracking
   - `track.title` → `.title3`/`.bold` (currently `.system(size: 17, .bold)`)
   - `track.artist` → `.subheadline`, `.white.opacity(0.75)`
   - time labels in `scrubberRow` → `.caption`, `.monospacedDigit()` (already monospaced; verify contrast)

4. **Progress bar** — `scrubberRow` uses a stock `Slider`. Replace with a
   thinner 2pt track + ~12pt thumb (custom `Gauge`/overlay or a `DragGesture`
   on a capsule). Keep the existing `playerVM.currentPosition` binding and
   `isScrubbing`/`seek(to:)` semantics.

5. **Margins** — `screenPanel` internal content: 16pt horizontal / 12pt
   vertical (currently 14pt horizontal in `trackMetadataStack`/channel HStack).
   8pt spacing between title and artist. `scrubberRow` 12pt top margin.

6. **Move attribution off the artwork** — extract `licenseRow` out of
   `trackMetadataStack` and render it as a small caption **below**
   `scrubberRow` (or in the existing more-options sheet). Removes the
   mid-artwork pill.

7. **Click wheel refinement** — `struct ClickWheel`: increase corner feel
   (it's a `Circle`), add inner shadow on the outer ring, bump the SF Symbols
   (`backward.fill`/`forward.fill`/`play.fill`/`line.3.horizontal`) to
   `.title2` scale. Outer ring `Color(.secondarySystemGroupedBackground)` →
   consider `#3A3A3C`; center `Color(.systemBackground)` → `#1C1C1E`.

8. **Color/contrast & a11y** — keep slate `#4A5568`. Secondary text
   `.white.opacity(0.75)`. Verify 4.5:1 contrast on the gradient; ensure the
   `ClickWheel` `SpatialTapGesture` regions stay ≥44×44pt; the wheel already
   has `.accessibilityElement`/actions — keep them.

## Quick wins (lowest risk, do first)

- Secondary text `.secondary`/system-gray → `.white.opacity(0.75)` in
  `trackMetadataStack` and the channel-description `Text`.
- Confirm `.monospacedDigit()` on both time labels in `scrubberRow`.
- The artwork gradient overlay is already in place (post the
  Rectangle+overlay+clipped fix) — verify opacity is strong enough.

## Constraints

- No local Swift/iOS compiler — every change is CI-validated (~15 min/cycle).
  Use `swiftc -parse` locally for syntax only.
- No XCUITest/snapshot infra: layout changes are **not** unit-testable; they
  require manual device verification from the TestFlight build.
- Single file: all edits are in `iPodView.swift` (plus optional named colors
  in `Assets.xcassets`).
