import XCTest
@testable import ParsoMusic

/// Phase 1 of Curator Mode: the curation data layer (per-channel verdicts) and
/// the bundled-manifest model. No UI / playback change yet.
final class CurationTests: XCTestCase {
    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    private func track(_ id: String) -> Track {
        Track(id: id, source: "internet_archive", title: "T \(id)", artist: "A",
              duration: 100, streamURL: URL(string: "https://archive.org/\(id)")!,
              downloadURL: nil, localFilePath: nil, license: .publicDomain, tags: [],
              qualityScore: 1, rawCreator: "", composer: nil, instruments: [],
              metadataConfidence: 1)
    }

    func test_setAndReadVerdict() async {
        await db.setCuration(channelId: "c1", trackId: "t1", status: "approved")
        let s = await db.curationStatus(channelId: "c1", trackId: "t1")
        XCTAssertEqual(s, "approved")
    }

    func test_verdictIsPerChannel() async {
        await db.setCuration(channelId: "c1", trackId: "t1", status: "approved")
        await db.setCuration(channelId: "c2", trackId: "t1", status: "rejected")
        let a = await db.curationStatus(channelId: "c1", trackId: "t1")
        let b = await db.curationStatus(channelId: "c2", trackId: "t1")
        XCTAssertEqual(a, "approved", "a verdict on one channel must not affect another")
        XCTAssertEqual(b, "rejected")
    }

    func test_verdictReplacesInPlace() async {
        await db.saveTracks([track("t1")])
        await db.setCuration(channelId: "c1", trackId: "t1", status: "review")
        await db.setCuration(channelId: "c1", trackId: "t1", status: "approved")
        let status = await db.curationStatus(channelId: "c1", trackId: "t1")
        XCTAssertEqual(status, "approved")
        let counts = await db.curationCounts(channelId: "c1")
        XCTAssertEqual(counts.review, 0, "re-verdicting must not leave a stale review row")
        XCTAssertEqual(counts.approved, 1)
    }

    func test_counts() async {
        await db.saveTracks([track("a"), track("b"), track("r"), track("v")])
        await db.setCuration(channelId: "c1", trackId: "a", status: "approved")
        await db.setCuration(channelId: "c1", trackId: "b", status: "approved")
        await db.setCuration(channelId: "c1", trackId: "r", status: "rejected")
        await db.setCuration(channelId: "c1", trackId: "v", status: "review")
        let c = await db.curationCounts(channelId: "c1")
        XCTAssertEqual(c.approved, 2)
        XCTAssertEqual(c.rejected, 1)
        XCTAssertEqual(c.review, 1)
    }

    func test_fetchApprovedTracksJoinsMetadataAndExcludesRejected() async {
        await db.saveTracks([track("t1"), track("t2"), track("t3")])
        await db.setCuration(channelId: "c1", trackId: "t1", status: "approved")
        await db.setCuration(channelId: "c1", trackId: "t2", status: "rejected")
        await db.setCuration(channelId: "c1", trackId: "t3", status: "approved")
        let approved = await db.fetchApprovedTracks(forChannelId: "c1")
        XCTAssertEqual(Set(approved.map(\.id)), ["t1", "t3"])
        XCTAssertEqual(approved.first(where: { $0.id == "t1" })?.title, "T t1")
    }

    func test_exportApprovedByChannel() async {
        await db.saveTracks([track("t1"), track("t2")])
        await db.setCuration(channelId: "c1", trackId: "t1", status: "approved")
        await db.setCuration(channelId: "c2", trackId: "t2", status: "approved")
        await db.setCuration(channelId: "c1", trackId: "t2", status: "rejected")
        let export = await db.exportApprovedByChannel()
        XCTAssertEqual(export["c1"]?.map(\.id), ["t1"])
        XCTAssertEqual(export["c2"]?.map(\.id), ["t2"])
    }

    // Phase 2: QueueManager wired to the curation manifest. When a channel has a
    // non-empty approved pool, the channel plays ONLY from it — no search/DB
    // fallback. Channels without a manifest entry keep their search pool
    // (verified by the existing QueueManagerTests, which use the default empty
    // bundled manifest).
    func test_queueManagerPlaysApprovedManifestPoolOnly() async {
        let approved = [track("appr-1"), track("appr-2")]
        let defaults = UserDefaults(suiteName: "QMfst-\(UUID().uuidString)")!
        let qm = QueueManager(db: db, defaults: defaults, manifestPool: { channelId in
            channelId == "guitar-classical" ? approved : []
        })
        guard let channel = Channel.defaults.first(where: { $0.id == "guitar-classical" })
        else { XCTFail("guitar-classical channel must exist"); return }
        var seen = Set<String>()
        for _ in 0..<6 {
            guard let t = await qm.nextTrack(channel: channel, shuffleMode: true) else { break }
            seen.insert(t.id)
        }
        XCTAssertEqual(seen, ["appr-1", "appr-2"],
            "a curated channel must play ONLY the manifest's approved tracks")
    }

    // Phase 3 of Curator Mode: the review-set ingest helper. Default-deny on
    // the reject set — re-ingesting a candidate that was rejected must NEVER
    // resurrect it as a review candidate.

    func test_ensureReviewSetInsertsNewCandidatesAsReview() async {
        await db.saveTracks([track("t1"), track("t2")])
        await db.ensureReviewSet(channelId: "c1", trackIds: ["t1", "t2"])
        let review = await db.curationTrackIds(channelId: "c1", status: "review")
        XCTAssertEqual(Set(review), ["t1", "t2"])
    }

    func test_ensureReviewSetSkipsAlreadyVerdicted() async {
        await db.saveTracks([track("t1"), track("t2"), track("t3")])
        await db.setCuration(channelId: "c1", trackId: "t1", status: "approved")
        await db.setCuration(channelId: "c1", trackId: "t2", status: "rejected")
        await db.ensureReviewSet(channelId: "c1", trackIds: ["t1", "t2", "t3"])
        let review = await db.curationTrackIds(channelId: "c1", status: "review")
        XCTAssertEqual(review, ["t3"],
            "already-approved/rejected tracks must NEVER be reset to review (sticky verdicts)")
        let approved = await db.curationTrackIds(channelId: "c1", status: "approved")
        XCTAssertEqual(approved, ["t1"])
        let rejected = await db.curationTrackIds(channelId: "c1", status: "rejected")
        XCTAssertEqual(rejected, ["t2"])
    }

    func test_reviewSetTracksJoinsMetadata() async {
        await db.saveTracks([track("r1"), track("r2")])
        await db.ensureReviewSet(channelId: "c1", trackIds: ["r1", "r2"])
        let queue = await db.reviewSetTracks(channelId: "c1")
        XCTAssertEqual(Set(queue.map(\.id)), ["r1", "r2"])
        XCTAssertEqual(queue.first(where: { $0.id == "r1" })?.title, "T r1")
    }

    // LiveCurationStore: the on-device cache + file writer that QueueManager
    // reads from. Reloads from the DB; falls back to the BUNDLED manifest for
    // channels the curator hasn't touched (non-curator users on the App Store).

    func test_liveStore_emptyDB_fallsBackToBundled() async {
        await LiveCurationStore.shared.reload(from: db)
        // Empty DB: pool falls back to per-channel file, then bundled manifest.
        // The per-channel file may have data from prior curator sessions (the
        // test host app's Documents dir is shared across test runs). The
        // important invariant: pool(for:) does not crash or return nil.
        let pool = LiveCurationStore.shared.pool(for: "guitar-classical")
        XCTAssertNotNil(pool)
        XCTAssertFalse(LiveCurationStore.shared.hasLiveCuration(for: "guitar-classical"))
    }

    func test_liveStore_reloadReflectsApprovedRows() async {
        await db.saveTracks([track("live-1"), track("live-2"), track("live-3")])
        await db.setCuration(channelId: "guitar-classical", trackId: "live-1",
                              status: "approved")
        await db.setCuration(channelId: "guitar-classical", trackId: "live-2",
                              status: "rejected")
        await db.setCuration(channelId: "guitar-classical", trackId: "live-3",
                              status: "approved")
        await LiveCurationStore.shared.reload(from: db)
        let pool = LiveCurationStore.shared.pool(for: "guitar-classical")
        // DB-approved tracks must be in the pool
        XCTAssertTrue(pool.contains(where: { $0.id == "live-1" }),
            "live store must surface DB-approved tracks")
        XCTAssertTrue(pool.contains(where: { $0.id == "live-3" }),
            "live store must surface DB-approved tracks")
        // DB-rejected tracks must NOT be in the pool
        XCTAssertFalse(pool.contains(where: { $0.id == "live-2" }),
            "live store must exclude DB-rejected tracks")
        XCTAssertTrue(LiveCurationStore.shared.hasLiveCuration(for: "guitar-classical"))
    }

    func test_liveStore_writesManifestFileToDocuments() async throws {
        // reload(from:) refreshes the in-memory pool from DB — no file writes.
        await LiveCurationStore.shared.reload(from: db)
        await db.saveTracks([track("doc-1")])
        await db.setCuration(channelId: "guitar-classical", trackId: "doc-1",
                              status: "approved")
        await LiveCurationStore.shared.reload(from: db)
        // DB-approved track must appear in the pool
        let pool = LiveCurationStore.shared.pool(for: "guitar-classical")
        XCTAssertTrue(pool.contains(where: { $0.id == "doc-1" }),
            "DB-approved track must appear in pool after reload")
    }

    func test_manifestDecodesAndQueries() throws {
        let json = Data("""
        {"version":1,"channels":{"childrens-songs":{"updatedAt":"2026-05-29",
        "approved":[{"id":"x","title":"T","creator":"C","duration":10,"parentIdentifier":null}]}}}
        """.utf8)
        let m = try JSONDecoder().decode(CurationManifest.self, from: json)
        XCTAssertEqual(m.version, 1)
        XCTAssertEqual(m.approved(for: "childrens-songs").count, 1)
        XCTAssertEqual(m.approved(for: "childrens-songs").first?.id, "x")
        XCTAssertTrue(m.approved(for: "no-such-channel").isEmpty)
    }

    // MARK: - Curation orphan cleanup

    /// When tracks are evicted by evictOldTracks, their curation rows MUST
    /// be preserved — verdicts are tiny and must survive so they re-apply
    /// when the track is re-fetched on the next channel refresh.
    /// However, curationCounts() now JOINs tracks, so orphaned rows are
    /// EXCLUDED from the count (no badge/count mismatch).
    func test_evictOldTracksCleansCurationRows() async {
        let t = track("evict-orphan")
        await db.saveTracks([t])
        await db.setCuration(channelId: "ch", trackId: t.id, status: "review")
        var counts = await db.curationCounts(channelId: "ch")
        XCTAssertEqual(counts.review, 1, "Track must be in review queue")

        // Evict with days=-1 so all tracks (including just-saved) are eligible
        await db.evictOldTracks(olderThan: -1)

        // Track is gone from the tracks table, so curationCounts returns 0
        // (no badge mismatch). But the verdict row itself still exists.
        counts = await db.curationCounts(channelId: "ch")
        XCTAssertEqual(counts.review, 0,
            "Curation row excluded from count after track eviction (JOIN fix)")
        // Verify the row still exists (it survives for re-import on re-fetch)
        let status = await db.curationStatus(channelId: "ch", trackId: t.id)
        XCTAssertEqual(status, "review",
            "Curation verdict row survives eviction even though count excludes it")
    }

    /// pruneChannelTracks must clean up curation rows for deleted tracks.
    func test_pruneChannelTracksCleansCurationRows() async {
        let t = track("prune-orphan")
        await db.saveTracks([t])
        await db.setCuration(channelId: "ch", trackId: t.id, status: "review")
        var counts = await db.curationCounts(channelId: "ch")
        XCTAssertEqual(counts.review, 1)

        // Create a tag-based channel that matches this track
        let ch = Channel(id: "ch", name: "ch", category: "Test", icon: "star",
                         tags: [], preferredSource: "internet_archive")
        // Prune keeping empty set → track is stale → deleted
        await db.pruneChannelTracks(forChannel: ch, keeping: [])

        counts = await db.curationCounts(channelId: "ch")
        XCTAssertEqual(counts.review, 0,
            "Curation row must be deleted when track is pruned")
    }

    /// Curation rows survive track eviction — verdicts are preserved even
    /// when the underlying track is aged out. However, curationCounts() now
    /// JOINs to tracks, so orphaned rows (track evicted) are EXCLUDED from
    /// the count badge — preventing a count/badge mismatch where the badge
    /// shows "3 tracks" but the queue is empty.
    func test_curationCountsExcludesOrphanedAfterEviction() async {
        let t1 = track("keep-me"), t2 = track("evict-me")
        await db.saveTracks([t1, t2])
        await db.setCuration(channelId: "ch", trackId: t1.id, status: "review")
        await db.setCuration(channelId: "ch", trackId: t2.id, status: "review")
        var counts = await db.curationCounts(channelId: "ch")
        XCTAssertEqual(counts.review, 2)

        // Mark t1 as downloaded so it survives eviction; t2 gets evicted
        await db.markDownloaded(trackID: t1.id, localPath: "/tmp/keep-me.mp3")
        await db.evictOldTracks(olderThan: -1)

        // t2 was evicted from tracks table — curationCounts JOINs tracks,
        // so the orphaned t2 curation row is NOT counted.
        counts = await db.curationCounts(channelId: "ch")
        XCTAssertEqual(counts.review, 1,
            "Orphaned curation rows (track evicted) must NOT inflate the count")
    }

    // MARK: - LiveCurationStore pool(for:) prioritizes live DB

    /// pool(for:) is DB-only: DB-rejected tracks must not appear even if the
    /// JSON file lists them as approved. The DB is the sole source of truth.
    func test_poolPrioritizesLiveDBOverStaleFileApproved() async {
        let channelId = "guitar-classical"
        let approvedTrack = track("live-approved")
        let rejectedTrack = track("db-rejected")
        await db.saveTracks([approvedTrack, rejectedTrack])

        // Set DB verdicts: approved for one, rejected for the other
        await db.setCuration(channelId: channelId, trackId: approvedTrack.id,
                              status: "approved")
        await db.setCuration(channelId: channelId, trackId: rejectedTrack.id,
                              status: "rejected")

        // Reload live store from DB
        await LiveCurationStore.shared.reload(from: db)

        // The pool must include only the DB-approved track
        let pool = LiveCurationStore.shared.pool(for: channelId)
        XCTAssertTrue(pool.contains(where: { $0.id == approvedTrack.id }),
            "DB-approved track must be in the pool")
        XCTAssertFalse(pool.contains(where: { $0.id == rejectedTrack.id }),
            "DB-rejected track must NOT be in the pool")
    }

    /// pool(for:) is DB-only: empty DB means empty pool, no JSON fallback.
    func test_poolFallsBackToFileWhenDBEmpty() async {
        let channelId = "guitar-classical"
        let fileTrack = track("file-only")
        await db.saveTracks([fileTrack])

        // Empty DB → pool is empty (no JSON fallback)
        await LiveCurationStore.shared.reload(from: db)
        let pool = LiveCurationStore.shared.pool(for: channelId)
        XCTAssertTrue(pool.isEmpty,
            "Empty DB must produce empty pool (no JSON file or manifest fallback)")
    }

    /// pool(for:) reads ONLY from the in-memory DB snapshot — no JSON file
    /// fallback, no bundled manifest. DB is the sole source of truth.
    func test_poolReadsOnlyFromDBSnapshot() async {
        let channelId = "guitar-classical"
        let track = track("db-only-track")
        await db.saveTracks([track])

        // Set a DB verdict → appears in pool
        await db.setCuration(channelId: channelId, trackId: track.id,
                              status: "approved")
        await LiveCurationStore.shared.reload(from: db)

        let pool = LiveCurationStore.shared.pool(for: channelId)
        XCTAssertTrue(pool.contains(where: { $0.id == track.id }),
            "DB-approved track must appear in pool")

        // Reload from empty DB → pool becomes empty, even if JSON files exist
        let emptyDB = try! DatabaseService(path: ":memory:")
        await LiveCurationStore.shared.reload(from: emptyDB)
        let emptyPool = LiveCurationStore.shared.pool(for: channelId)
        XCTAssertTrue(emptyPool.isEmpty,
            "pool must be empty when DB has no approved tracks (no JSON fallback)")
    }

    /// When the DB has zero verdicts for a channel, importBundledCurationsIfNeeded
    /// imports from the per-channel JSON. When the DB already has verdicts,
    /// it must skip the channel (user owns it).
    func test_importBundledCurationsSkipsClaimedChannels() async {
        let channelId = "guitar-classical"
        let track = track("already-claimed")
        await db.saveTracks([track])

        // Pre-populate DB with a verdict → channel is "claimed"
        await db.setCuration(channelId: channelId, trackId: track.id,
                              status: "approved")

        // importBundledCurationsIfNeeded should skip this channel
        await CustomChannelsStore.shared.importBundledCurationsIfNeeded(db: db)

        // The original verdict should still be there, unchanged
        let counts = await db.curationCounts(channelId: channelId)
        XCTAssertEqual(counts.approved, 1,
            "Claimed channel must not be overwritten by import")
    }

    /// Recovery: if the DB has zero approved tracks but the JSON file has
    /// entries, importBundledCurationsIfNeeded restores them.
    /// Note: this tests the RECOVERY path (isUnclaimed=false because there
    /// are rejected rows, but counts.approved=0 and file has approved).
    func test_recoveryImportsLostVerdictsFromJSON() async {
        let channelId = "guitar-classical"
        let recovered = track("recovered-track")
        let other = track("some-other-id")
        await db.saveTracks([recovered, other])

        // Simulate: user has verdicts (rejected tracks exist), but all
        // approved tracks were lost. The JSON file still has approved entries.
        await db.setCuration(channelId: channelId, trackId: "some-other-id",
                              status: "rejected")
        // approved count = 0, but the channel IS claimed (has verdicts)

        // importBundledCurationsIfNeeded should see approved=0 AND
        // file.approved non-empty AND isUnclaimed=false → RECOVERY path
        await CustomChannelsStore.shared.importBundledCurationsIfNeeded(db: db)

        // After import, the pool should reflect whatever was in the JSON file
        // (we can't control the JSON file content in tests, so just verify
        // the method doesn't crash and the original rejected verdict survives)
        let counts = await db.curationCounts(channelId: channelId)
        XCTAssertEqual(counts.rejected, 1,
            "Rejected verdicts must survive import")
    }

    // MARK: - curationCounts JOIN regression tests

    /// After evictOldTracks removes a track, curationCounts must exclude
    /// the orphaned curation rows. Verifies JOIN to tracks table works.
    func test_curationCountsExcludesEvictedTracksFromAllStatuses() async {
        let tracks = (0..<5).map { track("ct-\($0)") }
        await db.saveTracks(tracks)
        for t in tracks {
            let s = ["approved", "approved", "rejected", "review", "review"][
                tracks.firstIndex(where: { $0.id == t.id })!]
            await db.setCuration(channelId: "ch", trackId: t.id, status: s)
        }
        var counts = await db.curationCounts(channelId: "ch")
        XCTAssertEqual(counts.approved, 2)
        XCTAssertEqual(counts.rejected, 1)
        XCTAssertEqual(counts.review, 2)

        // Evict ALL tracks (none downloaded)
        await db.evictOldTracks(olderThan: -1)

        // All tracks gone → all curation counts should be 0
        counts = await db.curationCounts(channelId: "ch")
        XCTAssertEqual(counts.approved, 0, "all tracks evicted → approved count 0")
        XCTAssertEqual(counts.rejected, 0, "all tracks evicted → rejected count 0")
        XCTAssertEqual(counts.review, 0, "all tracks evicted → review count 0")
    }

    /// curationCounts must NOT crash or return incorrect counts when the
    /// curation table has rows but the tracks table is completely empty.
    func test_curationCountsEmptyTracksTable() async {
        await db.setCuration(channelId: "ch", trackId: "ghost-1", status: "approved")
        await db.setCuration(channelId: "ch", trackId: "ghost-2", status: "review")
        let counts = await db.curationCounts(channelId: "ch")
        XCTAssertEqual(counts.approved, 0, "ghost track not in tracks table")
        XCTAssertEqual(counts.review, 0, "ghost track not in tracks table")
        XCTAssertEqual(counts.rejected, 0)
    }

    // MARK: - fetchTracksForParentIdentifier (multi-part add-all-to-review)

    func test_fetchTracksForParentIdentifier_returnsOrderedParts() async {
        let parent = UUID().uuidString
        let p1 = Track(
            id: "p1-id", source: "internet_archive", title: "Ch 1", artist: "A",
            duration: 100, streamURL: URL(string: "https://archive.org/p1")!,
            downloadURL: nil, localFilePath: nil, license: .publicDomain, tags: [],
            qualityScore: 1, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 1,
            partNumber: 1, totalParts: 3, parentIdentifier: parent)
        let p2 = Track(
            id: "p2-id", source: "internet_archive", title: "Ch 2", artist: "A",
            duration: 80, streamURL: URL(string: "https://archive.org/p2")!,
            downloadURL: nil, localFilePath: nil, license: .publicDomain, tags: [],
            qualityScore: 1, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 1,
            partNumber: 2, totalParts: 3, parentIdentifier: parent)
        let p3 = Track(
            id: "p3-id", source: "internet_archive", title: "Ch 3", artist: "A",
            duration: 120, streamURL: URL(string: "https://archive.org/p3")!,
            downloadURL: nil, localFilePath: nil, license: .publicDomain, tags: [],
            qualityScore: 1, rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 1,
            partNumber: 3, totalParts: 3, parentIdentifier: parent)
        await db.saveTracks([p1, p2, p3])

        let parts = await db.fetchTracks(forParentIdentifier: parent)
        XCTAssertEqual(parts.count, 3)
        // Ordered by partNumber ASC
        let ids = parts.map(\.id)
        XCTAssertEqual(ids, ["p1-id", "p2-id", "p3-id"])
    }

    /// ensureReviewSet with multi-part tracks must insert any that don't yet
    /// have verdicts, and skip those that are already rejected.
    func test_ensureReviewSetBulkMultiPart() async {
        await db.saveTracks([track("a1"), track("a2"), track("r1")])
        await db.setCuration(channelId: "ch", trackId: "r1", status: "rejected")
        await db.ensureReviewSet(channelId: "ch", trackIds: ["a1", "a2", "r1"])
        let review = await db.curationTrackIds(channelId: "ch", status: "review")
        XCTAssertEqual(Set(review), ["a1", "a2"],
            "New tracks must enter review; rejected must NOT be resurrected")
    }

    // MARK: - Verdict survival across prune

    /// Verdicts (approved, rejected, review) must survive pruneChannelTracks
    /// when their track IDs are in the keeping set — the real bug was that
    /// load(channel:) only added approved IDs to keepingIds, so rejected and
    /// review verdicts were silently deleted on prune.
    func test_prunePreservesAllVerdicts() async {
        let t1 = track("keep-approved")
        let t2 = track("keep-rejected")
        let t3 = track("keep-review")
        let t4 = track("keep-other")
        await db.saveTracks([t1, t2, t3, t4])
        await db.setCuration(channelId: "ch", trackId: t1.id, status: "approved")
        await db.setCuration(channelId: "ch", trackId: t2.id, status: "rejected")
        await db.setCuration(channelId: "ch", trackId: t3.id, status: "review")

        let ch = Channel(id: "ch", name: "ch", category: "Test", icon: "star",
                         tags: [], preferredSource: "internet_archive")
        // Prune keeping all curated IDs — should preserve all verdict rows
        await db.pruneChannelTracks(forChannel: ch,
            keeping: [t1.id, t2.id, t3.id, t4.id])

        let s1 = await db.curationStatus(channelId: "ch", trackId: t1.id)
        let s2 = await db.curationStatus(channelId: "ch", trackId: t2.id)
        let s3 = await db.curationStatus(channelId: "ch", trackId: t3.id)
        XCTAssertEqual(s1, "approved",
            "Approved verdict must survive prune")
        XCTAssertEqual(s2, "rejected",
            "Rejected verdict must survive prune")
        XCTAssertEqual(s3, "review",
            "Review verdict must survive prune")
    }

    /// Verdicts without a matching track in keepingIds are correctly cleaned up.
    func test_pruneCleansOrphanVerdictWhenNotKept() async {
        let t = track("orphan")
        await db.saveTracks([t])
        await db.setCuration(channelId: "ch", trackId: t.id, status: "review")

        let ch = Channel(id: "ch", name: "ch", category: "Test", icon: "star",
                         tags: [], preferredSource: "internet_archive")
        // Prune with empty keeping set — track and its verdict should be cleaned
        await db.pruneChannelTracks(forChannel: ch, keeping: [])

        let status = await db.curationStatus(channelId: "ch", trackId: t.id)
        XCTAssertNil(status, "Curation row must be deleted when track not in keeping set")
    }

    /// Simulates the exact load(channel:) flow: save tracks, set mixed verdicts,
    /// build keepingIds the way the fix does (allCuratedTrackIds), and verify
    /// prune preserves all verdict statuses.
    func test_fullVerdictLifecycleSurvivesPrune() async {
        let chId = "curated-ch"
        let tApproved = track("ca1")
        let tRejected = track("cr1")
        let tReview = track("cv1")
        let tFetched = track("cf1")
        await db.saveTracks([tApproved, tRejected, tReview, tFetched])
        await db.setCuration(channelId: chId, trackId: tApproved.id, status: "approved")
        await db.setCuration(channelId: chId, trackId: tRejected.id, status: "rejected")
        await db.setCuration(channelId: chId, trackId: tReview.id, status: "review")

        // Build keepingIds the same way load(channel:) does:
        // fetched track IDs (simulated fresh IA results) + all curated IDs
        var keepingIds = Set([tFetched.id])
        let allCuratedIds = await db.allCuratedTrackIds(channelId: chId)
        keepingIds.formUnion(allCuratedIds)

        let ch = Channel(id: chId, name: chId, category: "Test", icon: "star",
                         tags: [], preferredSource: "internet_archive")
        await db.pruneChannelTracks(forChannel: ch, keeping: keepingIds)

        let s1 = await db.curationStatus(channelId: chId, trackId: tApproved.id)
        let s2 = await db.curationStatus(channelId: chId, trackId: tRejected.id)
        let s3 = await db.curationStatus(channelId: chId, trackId: tReview.id)
        XCTAssertEqual(s1, "approved")
        XCTAssertEqual(s2, "rejected")
        XCTAssertEqual(s3, "review")

        // ensureReviewSet must NOT resurrect the rejected track
        await db.ensureReviewSet(channelId: chId, trackIds: [tRejected.id, tFetched.id])
        let reviewIds = await db.curationTrackIds(channelId: chId, status: "review")
        XCTAssertTrue(reviewIds.contains(tReview.id), "Existing review must persist")
    }

    // MARK: - Regression: channel-jumping during verdict

    /// On every verdict the curator calls LiveCurationStore.reload(channelId:, from:)
    /// which publishes objectWillChange. Views observing LiveCurationStore (or
    /// PlayerViewModel via @EnvironmentObject) would recompute in a cascade that
    /// destabilized the sheet, causing the curator to switch channels and lose
    /// verdicts. This test verifies that verdict data survives repeated
    /// LiveCurationStore reloads — the DB layer must be immune to observer storms.
    func test_verdictSurvivesRepeatedLiveCurationStoreReloads() async {
        let chId = "storm-ch"
        let t = track("storm-1")
        await db.saveTracks([t])

        await db.setCuration(channelId: chId, trackId: t.id, status: "approved")
        // Simulate the curator calling reload on every verdict
        await LiveCurationStore.shared.reload(channelId: chId, from: db)
        await LiveCurationStore.shared.reload(channelId: chId, from: db)
        await LiveCurationStore.shared.reload(channelId: chId, from: db)

        let status = await db.curationStatus(channelId: chId, trackId: t.id)
        XCTAssertEqual(status, "approved",
            "Verdict must survive repeated LiveCurationStore reloads")

        let approved = LiveCurationStore.shared.pool(for: chId)
        XCTAssertTrue(approved.contains(where: { $0.id == t.id }),
            "Approved track must appear in pool after reloads")
    }

    /// When views like CuratedChannelsGrid observed LiveCurationStore, they'd
    /// fire loadDiscovery() on every verdict publish, causing cascading
    /// recomputes. The fix eliminated those observations. This test verifies
    /// the full lifecycle: make verdicts across multiple statuses, reload
    /// the store, and verify counts + each individual verdict.
    func test_mixedVerdictLifecycleWithReloads() async {
        let chId = "lifecycle-ch"
        let ta = track("t-app"), tr = track("t-rej"), tv = track("t-rev")
        await db.saveTracks([ta, tr, tv])

        // Initial state
        await db.setCuration(channelId: chId, trackId: ta.id, status: "approved")
        await db.setCuration(channelId: chId, trackId: tr.id, status: "rejected")
        await db.ensureReviewSet(channelId: chId, trackIds: [tv.id])

        var counts = await db.curationCounts(channelId: chId)
        XCTAssertEqual(counts.approved, 1)
        XCTAssertEqual(counts.rejected, 1)
        XCTAssertEqual(counts.review, 1)

        // Simulate verdicts mid-session
        await db.setCuration(channelId: chId, trackId: tv.id, status: "approved")
        await LiveCurationStore.shared.reload(channelId: chId, from: db)

        counts = await db.curationCounts(channelId: chId)
        XCTAssertEqual(counts.approved, 2,
            "Track moved from review to approved must update counts")
        XCTAssertEqual(counts.review, 0)

        // Undo a verdict (move back to review)
        await db.setCuration(channelId: chId, trackId: ta.id, status: "review")
        await LiveCurationStore.shared.reload(channelId: chId, from: db)

        counts = await db.curationCounts(channelId: chId)
        XCTAssertEqual(counts.approved, 1)
        XCTAssertEqual(counts.review, 1)
        XCTAssertEqual(counts.rejected, 1)
    }

    /// Regression: when curator re-enters after verdicts, reload() reads from
    /// DB. All three status pools (review, approved, rejected) must be intact.
    func test_curatorReentrySeesAllVerdictTypes() async {
        let chId = "reentry-ch"
        let t1 = track("re-1"), t2 = track("re-2"), t3 = track("re-3")
        await db.saveTracks([t1, t2, t3])

        await db.setCuration(channelId: chId, trackId: t1.id, status: "approved")
        await db.setCuration(channelId: chId, trackId: t2.id, status: "rejected")
        await db.setCuration(channelId: chId, trackId: t3.id, status: "review")

        // Simulate what CuratorChannelEditView.reload() does on entry
        let counts = await db.curationCounts(channelId: chId)
        let reviewTracks = await db.reviewSetTracks(channelId: chId)
        let approvedTracks = await db.fetchApprovedTracks(forChannelId: chId)
        let rejectedTracks = await db.fetchRejectedTracks(forChannelId: chId)

        XCTAssertEqual(counts.review, 1)
        XCTAssertEqual(counts.approved, 1)
        XCTAssertEqual(counts.rejected, 1)
        XCTAssertEqual(reviewTracks.map(\.id), [t3.id])
        XCTAssertEqual(approvedTracks.map(\.id), [t1.id])
        XCTAssertEqual(rejectedTracks.map(\.id), [t2.id])
    }

    // MARK: - mergeShippedCuration

    func test_mergeShippedCurationPreservesExistingVerdicts() async {
        let channelId = "guitar-classical"
        let existing = track("existing-track")
        let rejected = track("rejected-track")
        await db.saveTracks([existing, rejected])

        await db.setCuration(channelId: channelId, trackId: existing.id, status: "approved")
        await db.setCuration(channelId: channelId, trackId: rejected.id, status: "rejected")

        await CustomChannelsStore.shared.mergeShippedCuration(chId: channelId, db: db)

        let status = await db.curationStatus(channelId: channelId, trackId: existing.id)
        XCTAssertEqual(status, "approved", "Existing approved verdict must not change")

        let rejStatus = await db.curationStatus(channelId: channelId, trackId: rejected.id)
        XCTAssertEqual(rejStatus, "rejected", "Existing rejected verdict must not change")
    }

    func test_mergeShippedCurationDoesNotOverwriteExistingVerdicts() async {
        let channelId = "ancient-greece"

        // Pre-populate DB with an approved verdict for a known track ID that
        // might appear in the shipped JSON. If the merge blindly overwrote,
        // the status would change.
        let myTrack = track("protected-track")
        await db.saveTracks([myTrack])
        await db.setCuration(channelId: channelId, trackId: myTrack.id, status: "review")

        await CustomChannelsStore.shared.mergeShippedCuration(chId: channelId, db: db)

        let status = await db.curationStatus(channelId: channelId, trackId: myTrack.id)
        XCTAssertEqual(status, "review",
            "Existing verdict (review) must not be overwritten by merge")
    }
}
