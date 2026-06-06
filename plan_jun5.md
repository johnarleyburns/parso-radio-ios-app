# June 5 Implementation Plan

## Created Assets
- `lorewave-privacy.html` — full privacy policy for hosting at parso.guru
- `FOR_APPSTORE_REVIEWERS.md` — reviewer-facing document
- `CONTRIBUTIONS-SETUP.md` — restored from git history
- `CONTRIBUTIONS-PROPOSAL.md` — restored from git history
- `ParsoRadio.storekit` — StoreKit configuration for local sandbox testing

---

## PHASE 1: Curation Bug Fixes

### Bug 1: Track failure doesn't advance to next track
**Files:** PlayerViewModel.swift, CuratedChannelsListView.swift, CuratorModeView.swift
**Tests needed:** Test that failedAuditionTrackId signal triggers auto-advance in curator views

### Bug 2: Undo reloads entire screen
**Files:** CuratedChannelsListView.swift
**Tests needed:** Test that undoVerdict updates only one row, does not reassign queue

### Bug 3: Return from curation plays wrong track
**Files:** PlayerViewModel.swift
**Tests needed:** Test that preAuditionState is preserved across multiple auditionTrack() calls

---

## PHASE 2: Age Assurance

### Xcode entitlement + service + view
**Files:** AgeAssuranceService.swift, AgeGateView.swift, ParsoRadioApp.swift, KidsModeController.swift
**Tests needed:** AgeAssuranceServiceTests for bracket logic and fallback behavior

---

## PHASE 3: Supporter Badges

### Subscription tier + badge UI
**Files:** ContributionStore.swift, iPodView.swift, SettingsView.swift, AboutView.swift
**Tests needed:** ContributionStore tests for subscription tier detection

---

## PHASE 4: Privacy Policy Deployment
**Files:** AboutView.swift (link update)
**Manual:** Upload lorewave-privacy.html to parso.guru
