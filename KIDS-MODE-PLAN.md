# Kids Mode — Plan

**Why it's core:** the mission includes kids in low-income regions who want
audiobooks and songs and can't pay. Kids Mode makes the phone safe to hand to a
child: only the children's channels, no search into the wider Internet Archive,
no news, no purchase prompts — all behind a parent PIN.

## Behavior

When **Kids Mode is ON**:
- The menu shows ONLY the children's channels — `childrens-songs` and
  `childrens-books` (a single short list, no categories, no Library/Settings).
- **Search is gone** (the biggest hazard — IA search can surface mature audio).
- **News / Lectures / For You / Ambient / other Curated** are unreachable.
- The **Support/contribution toast is suppressed** and the purchase flow isn't
  reachable (no accidental kid purchases).
- On launch the app loads a children's channel (the last kids channel if there
  was one, else Children's Songs) instead of restoring an arbitrary last session.
- Exiting requires the **parent PIN**.

## Components

1. **`KidsModeController`** (`@MainActor`, shared `ObservableObject`, like
   `NetworkMonitor`): `isEnabled` (UserDefaults), a 4-digit PIN (UserDefaults —
   this is a parental gate, not a security boundary), `enable(pin:)`,
   `disable(pin:) -> Bool`, `verify(pin:)`, and `allowedChannelIDs`
   = `{childrens-songs, childrens-books}` + `allowedChannels()`.
2. **`KidsMenuView`**: a minimal `NavigationStack` list of the allowed channels
   (big tappable rows) + a lock button → PIN alert to exit.
3. **`iPodView`**: the wheel MENU opens `KidsMenuView` (not `MainMenuView`) when
   enabled; launch loads a kids channel when enabled.
4. **`SettingsView`**: a "Kids Mode" section to enable (set PIN). Disable lives
   on the lock button in `KidsMenuView` (Settings isn't reachable while ON).
5. **`ParsoRadioApp`**: suppress the contribution toast + `evaluate()` when ON.

## Scope decisions (v1)

- PIN in UserDefaults (a parental gate; Keychain is overkill for v1).
- Enabling takes full effect on the next channel pick / launch — we do NOT
  yank a track the parent is currently playing. The parent enables it, picks a
  kids channel, then hands over.
- Downloaded playlists are NOT exposed in Kids Mode v1 (a playlist could hold
  anything). Future: allow playlists explicitly marked kid-safe.
- No age rating change required; iOS Screen Time + this combine well. (We can
  now honestly answer "Yes" to Parental Controls if we choose.)

## Tests (fast, single CI job)

- `KidsModeController`: enable sets PIN+flag; `disable` only with the right PIN;
  `verify`; `allowedChannels()` returns exactly the two children's channels.
- (Logic-level) launch-channel selection picks an allowed channel.
