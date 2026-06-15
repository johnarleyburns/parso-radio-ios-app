import XCTest
@testable import ParsoMusic

final class RecentlyPlayedTests: XCTestCase {

    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    func testEmptyHistoryReturnsEmpty() async {
        let tracks = await db.fetchRecentlyPlayedTracks()
        XCTAssertTrue(tracks.isEmpty)
    }

    func testOrderedByMostRecent() async throws {
        // Seed three tracks with stamped play times, oldest → newest.
        let t1 = makeTrack(id: "trk-1")
        let t2 = makeTrack(id: "trk-2")
        let t3 = makeTrack(id: "trk-3")
        await db.saveTracks([t1, t2, t3])

        await db.recordPlayed(channelId: "c1", trackId: t1.id)
        try await Task.sleep(nanoseconds: 30_000_000)   // ensure distinct timestamps
        await db.recordPlayed(channelId: "c1", trackId: t2.id)
        try await Task.sleep(nanoseconds: 30_000_000)
        await db.recordPlayed(channelId: "c1", trackId: t3.id)

        let recents = await db.fetchRecentlyPlayedTracks(limit: 10)
        XCTAssertEqual(recents.map(\.id), [t3.id, t2.id, t1.id],
                       "fetchRecentlyPlayedTracks must order newest first.")
    }

    func testDedupedAcrossChannels() async throws {
        // Same track played in two channels — should appear once, at the
        // timestamp of the more recent play.
        let t = makeTrack(id: "shared")
        let other = makeTrack(id: "other")
        await db.saveTracks([t, other])

        await db.recordPlayed(channelId: "ch-a", trackId: t.id)
        try await Task.sleep(nanoseconds: 30_000_000)
        await db.recordPlayed(channelId: "ch-b", trackId: t.id)
        try await Task.sleep(nanoseconds: 30_000_000)
        await db.recordPlayed(channelId: "ch-a", trackId: other.id)

        let recents = await db.fetchRecentlyPlayedTracks(limit: 10)
        XCTAssertEqual(recents.map(\.id), [other.id, t.id],
                       "Newest distinct plays first; duplicates collapsed.")
        XCTAssertEqual(Set(recents.map(\.id)).count, recents.count,
                       "Recently played must dedupe by track id.")
    }

    func testLimit() async throws {
        var ids: [String] = []
        for i in 0..<5 {
            let id = "trk-\(i)"
            ids.append(id)
            await db.saveTracks([makeTrack(id: id)])
            await db.recordPlayed(channelId: "ch", trackId: id)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let two = await db.fetchRecentlyPlayedTracks(limit: 2)
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two.map(\.id), ["trk-4", "trk-3"])
    }

    func testDeleteSingleTrackFromHistory() async throws {
        let a = makeTrack(id: "del-a")
        let b = makeTrack(id: "del-b")
        await db.saveTracks([a, b])
        await db.recordPlayed(channelId: "ch", trackId: a.id)
        try await Task.sleep(nanoseconds: 20_000_000)
        await db.recordPlayed(channelId: "ch", trackId: b.id)

        await db.deletePlayHistory(trackId: a.id)
        let recents = await db.fetchRecentlyPlayedTracks()
        XCTAssertEqual(recents.map(\.id), [b.id],
            "deletePlayHistory must remove a single track's history rows.")
    }

    func testDeleteRemovesAcrossAllChannels() async throws {
        let shared = makeTrack(id: "cross")
        await db.saveTracks([shared])
        await db.recordPlayed(channelId: "ch-a", trackId: shared.id)
        try await Task.sleep(nanoseconds: 10_000_000)
        await db.recordPlayed(channelId: "ch-b", trackId: shared.id)
        await db.deletePlayHistory(trackId: shared.id)
        let crossRecents = await db.fetchRecentlyPlayedTracks()
        XCTAssertTrue(crossRecents.isEmpty,
            "deletePlayHistory must remove every channel's row for the track.")
    }

    func testClearAllPlayHistory() async throws {
        for i in 0..<3 {
            let t = makeTrack(id: "clr-\(i)")
            await db.saveTracks([t])
            await db.recordPlayed(channelId: "c", trackId: t.id)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await db.clearAllPlayHistory()
        let afterClear = await db.fetchRecentlyPlayedTracks()
        XCTAssertTrue(afterClear.isEmpty)
    }

    func testJumpBackInShowsAfterPlayingTrack() async throws {
        let t = makeTrack(id: "jbi-1")
        await db.saveTracks([t])
        await db.recordPlayed(channelId: "c1", trackId: t.id)

        let recents = await db.fetchRecentlyPlayedTracks(limit: 10)
        XCTAssertFalse(recents.isEmpty, "Jump Back In should show when history exists")
        XCTAssertEqual(recents.first?.id, "jbi-1")
    }

    func testJumpBackInEmptyForFirstTimeVisitor() async throws {
        let recents = await db.fetchRecentlyPlayedTracks(limit: 10)
        XCTAssertTrue(recents.isEmpty, "Jump Back In should not show for first-time visitors")
    }

    private func makeTrack(id: String) -> Track {
        Track(
            id: id, source: "fma",
            title: "T-\(id)", artist: "A",
            duration: 120,
            streamURL: URL(string: "https://example.com/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .cc0, tags: [],
            qualityScore: 1.0,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0
        )
    }
}
