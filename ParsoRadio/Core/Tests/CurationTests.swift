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
        XCTAssertEqual(await db.curationStatus(channelId: "c1", trackId: "t1"), "approved")
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
