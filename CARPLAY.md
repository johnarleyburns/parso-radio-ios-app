# CarPlay — status, prerequisites, and how to finish it

_Branch: `carplay-support` (do NOT merge to `main` until step 1 below is done —
the entitlement breaks Release signing without a matching profile)._

## What this branch already contains (code-complete, `swiftc -parse` only)

- `ParsoRadio/ParsoRadio.entitlements` — declares `com.apple.developer.carplay-audio`.
- `project.yml` — wires `CODE_SIGN_ENTITLEMENTS`, flips
  `UIApplicationSupportsMultipleScenes` to `true`, and registers the CarPlay
  scene (`CPTemplateApplicationSceneSessionRoleApplication` →
  `$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate`).
- `ParsoRadio/App/CarPlaySceneDelegate.swift` — a `CPTemplateApplicationSceneDelegate`
  that mirrors the phone's channel browser as CarPlay list templates
  (categories → channels) and starts playback through the shared player.
- `ParsoRadio/App/ParsoRadioApp.swift` — `playerVM` hoisted to
  `ParsoMusicApp.sharedPlayerVM` so the car and the phone drive **one** player
  (one audio session, one Now-Playing state).

> ⚠️ This code is verified only with `swiftc -parse` (no local iOS toolchain;
> CI builds `main` only). It has **not** been compiled or run on a head
> unit/simulator. Expect to iterate once it can actually build (see step 4).

## Why it can't ship yet — the hard gate

CarPlay audio is an Apple-**granted** capability. The entitlement key in the
file is necessary but not sufficient: the **provisioning profile** used to sign
the Release build must also include it, and Apple only adds it after they
approve a request. Ship order matters:

### 1. Request the entitlement from Apple (you, on the web — I can't do this)
- Apple Developer account → **Certificates, Identifiers & Profiles**, or use the
  request form: <https://developer.apple.com/contact/carplay/> (select **CarPlay
  audio app**). Approval is manual and can take days to weeks.
- When granted, the **CarPlay** capability appears for App ID
  `guru.parso.ios-radio-app`; enable it.

### 2. Regenerate the provisioning profile + update CI
- Regenerate the **distribution** profile for that App ID so it includes the
  CarPlay entitlement.
- Re-encode it and update the **`CI_PROFILE`** GitHub secret (base64
  `.mobileprovision`), same as the other signing secrets in `.github/workflows/ios.yml`.

### 3. Merge `carplay-support` → `main`
Only after steps 1–2. Pushing to `main` triggers the build; if the profile
doesn't yet carry the entitlement, the **export/sign step fails** (and blocks
TestFlight) — which is the whole reason this is on a branch.

### 4. Test on the CarPlay simulator
- Xcode → run the app on an iPhone simulator → **I/O ▸ External Displays ▸
  CarPlay** to open the CarPlay window. Verify: categories list → channel list →
  tap plays and the Now-Playing screen appears with transport controls.
- Then test on a real head unit before submitting.

## Likely follow-ups once it compiles (notes for the iterate pass)

- **Now-Playing transport**: `CPNowPlayingTemplate` uses the standard
  `MPRemoteCommandCenter` commands — already configured in `AudioPlayerService`,
  so play/pause/skip should work for free. Confirm the ±15 s vs next/prev
  behavior matches content type in the car.
- **"Recently Played" / "Favorites" tabs**: consider a `CPTabBarTemplate` root
  with For You + Favorites + Browse, instead of a single category list.
- **CarPlay HIG limits**: list depth and item counts are capped by the system;
  long channel lists may need trimming/sectioning.
- **Scene API surface**: double-check `CPListItem` initializer labels,
  `handler` closure parameter type, and `CPListImageRowItem` if you want
  artwork rows — these are the bits most likely to need a tweak at first compile.

## Rollback

Nothing here touches `main`. If CarPlay is shelved, delete the branch; `main`
keeps shipping unaffected.
