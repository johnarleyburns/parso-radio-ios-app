# Fixes Plan — Post-Implementation Corrections

## 1. Alphabetical Order by Default
**Root cause:** `applyOrder()` only runs when `channelOrder` is empty (first launch). On subsequent launches, `loadMeta()` restores whatever order was saved — which may not be alphabetical. If the user accidentally reordered, there's no "reset to alphabetical" path.

**Fix:** 
- In `loadMeta()`, after loading saved order, verify it contains all current channel IDs. If there are new channels (from app updates), insert them in alphabetical position rather than appending.
- Also add a "Reset Order" action (long press on any row or settings) that clears `channelOrder` and reapplies alphabetical sort.
- In `saveMeta()`, always write the current order.

## 2. Non-Audio File Detection + Error Toast
**Root cause:** PDFs/non-audio files can appear in IA search results (any mediatype:audio search can return items where the actual downloadable file is a PDF). AVPlayer loads them, reaches `.readyToPlay` with zero duration, and the stall watchdog eventually skips them after 20s.

**Fix:**
- In `InternetArchiveService`, after fetching search results, filter out results where the format indicates non-audio (PDF, text, image). Check the `format` field in IA responses.
- In `PlayerViewModel.playTrack`, after the AVPlayerItem reaches `.readyToPlay`, check if `duration` is effectively zero (or the item has no audio tracks). If so, skip immediately with an error toast "Non-audio material — skipping".
- Show a non-intrusive toast/banner when a track is skipped for this reason.
- In the curator views, detect this case and surface "Non-audio" as a verdict label.

## 3. Full-Page IA Query Editor
**Root cause:** The alert with TextField is too small for typical IA queries which are 100-500+ characters.

**Fix:**
- Replace the "IA Search Query" alert with a `.sheet` presenting a full-page editor with a multiline `TextEditor` (not `TextField`).
- Pre-fill with the current query.
- "Save" and "Cancel" buttons in the toolbar.

## 4. Hamburger Menu Replacing Channel Settings Section + Search Icon
**Root cause:** The Channel Settings section takes up valuable list space, and the search icon in the toolbar is redundant.

**Fix:**
- Remove the "Channel Settings" section from the List.
- Remove the search magnifying-glass button from the toolbar (search is already available via "Search Archive.org to Add" button in the list).
- Add a hamburger/ellipsis menu (`...` icon or `ellipsis.circle`) in the top-right toolbar using `.contextMenu` or a `Menu` with `Menu` items:
  - "Edit Channel Name" → opens name edit alert
  - "Edit Search Query" → opens full-page query editor sheet

## 5. Search Results: Don't Show "Already Added" After Pressing
**Root cause:** `verdictLabel()` says "Already approved/rejected" even for verdicts set in the current session. The user pressed the button — they know they did it.

**Fix:**
- Track which verdicts were set in the CURRENT search session (separate from pre-existing verdicts).
- Show the verdict checkmark/X icon as filled after pressing, but don't show the "Already..." label for just-set verdicts.
- Only show "Already approved/rejected" labels for verdicts that existed BEFORE the search (loaded from DB in `search()`).

## 6. Toggle Verdict After Approval/Rejection
**Root cause:** `directVerdict` buttons are `.disabled(verdict == "approved" || verdict == "rejected")`, blocking changes.

**Fix:**
- Remove the `.disabled` modifier from both buttons.
- In `directVerdict`, if the track already has a different verdict, reverse the old verdict (e.g., if changing from rejected to approved, remove from rejected list, add to approved).
- Also remove from per-channel JSON file's other list when toggling.
- Update the DB accordingly (call `setCuration` with the new status — the old entry is overwritten because the (channelId, trackId) pair is unique).

## 7. Sort Review/Approved/Rejected Queues Alphabetically
**Root cause:** No `ORDER BY` in SQLite queries, no client-side sorting.

**Fix:**
- In `CuratorChannelEditView.reload()`, sort the loaded queue by `title` (case-insensitive) before assigning.
- Same in `CuratorReviewView.reload()`.
- This applies to all three filter modes (review, approved, rejected).

## 8. Channel Name Change Propagation to ChannelInfoView
**Root cause:** `ChannelInfoView` takes a `let channel: Channel` — a value type struct with `let name: String`. When the channel is renamed, the view already on screen doesn't observe the change. It needs to be re-navigated to with the new name.

**Fix:**
- Make `ChannelInfoView` observe `CustomChannelsStore.shared` for the current channel's name.
- For curated channels, look up the `ChannelMeta` by ID from the store and display its `name`, falling back to the passed-in `channel.name` for non-curated channels.
- Or simpler: pass `channel.id` to `ChannelInfoView` and have it look up the channel dynamically, getting the latest name from CustomChannelsStore for curated channels.

## Tests to Add

### CustomChannelsStoreTests (new file)
- `testApplyOrderAlphabeticalOnEmptyOrder` — verify alphabetical sort
- `testApplyOrderPreservesUserOrder` — verify user reorder is saved/restored
- `testNewChannelInsertedInOrder` — new bundled channels appear alphabetically
- `testRenameChannelUpdatesMeta`

### CuratorViewTests (new file)
- `testReviewQueueSortedAlphabetically` — verify reload returns sorted tracks
- `testApprovedQueueSortedAlphabetically`
- `testRejectedQueueSortedAlphabetically`

### CuratorSearchTests (extend existing or new)
- `testVerdictToggleApproveToReject` — approve, then reject, verify DB state
- `testVerdictToggleRejectToApprove`
- `testPreExistingVerdictNotMistakenForSession` — verify session verdicts don't show "Already" label

### PlayerViewModelTests (extend existing)
- `testNonAudioTrackDetectedAsSkip` — verify zero-duration tracks are skipped quickly

### ChannelInfoViewTests (new file)
- `testChannelNameUpdatesAfterRename` — rename a channel, verify ChannelInfoView shows new name
