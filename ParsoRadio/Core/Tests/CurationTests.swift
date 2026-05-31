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
        await db.setCuration(channelId: "c1", trackId: "t1", status: "review")
        await db.setCuration(channelId: "c1", trackId: "t1", status: "approved")
        let status = await db.curationStatus(channelId: "c1", trackId: "t1")
        XCTAssertEqual(status, "approved")
        let counts = await db.curationCounts(channelId: "c1")
        XCTAssertEqual(counts.review, 0, "re-verdicting must not leave a stale review row")
        XCTAssertEqual(counts.approved, 1)
    }

    func test_counts() async {
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
        // Empty DB + empty bundled curation.json → pool is empty.
        XCTAssertTrue(LiveCurationStore.shared.pool(for: "guitar-classical").isEmpty)
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
        XCTAssertEqual(Set(pool.map(\.id)), ["live-1", "live-3"],
            "live store must surface ONLY approved rows from the DB")
        XCTAssertTrue(LiveCurationStore.shared.hasLiveCuration(for: "guitar-classical"))
    }

    func test_liveStore_writesManifestFileToDocuments() async throws {
        // Wipe DB state to start clean.
        await LiveCurationStore.shared.reload(from: db)
        await db.saveTracks([track("doc-1")])
        await db.setCuration(channelId: "guitar-classical", trackId: "doc-1",
                              status: "approved")
        await LiveCurationStore.shared.reload(from: db)
        let url = LiveCurationStore.liveManifestURL
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(CurationManifest.self, from: data)
        XCTAssertEqual(manifest.version, 1)
        let approved = manifest.approved(for: "guitar-classical")
        XCTAssertTrue(approved.contains { $0.id == "doc-1" },
            "Documents/curation.json must include just-approved tracks (no app rebuild required)")
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
}
