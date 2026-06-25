import XCTest
@testable import ParsoMusic

/// Issue #3 / foundation: `fetchRecentlyPlayedWorks` collapses spoken-work
/// chapters under their parent identifier (one card per book/lecture/podcast)
/// while keeping music as one card per track, using the persisted media kind.
final class RecentlyPlayedWorksTests: XCTestCase {
    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    private func chapter(_ n: Int, parent: String) -> Track {
        var t = Track.makeStub(id: "\(parent)/ch_\(n).mp3",
                               title: "Chapter \(n)", parentIdentifier: parent)
        t.partNumber = n
        t.collectionTitle = "Gallipoli"
        return t
    }

    func testBookChaptersCollapseIntoOneWork() async throws {
        let chapters = [chapter(1, parent: "bk"), chapter(2, parent: "bk"), chapter(3, parent: "bk")]
        let music = Track.makeStub(id: "song-1", title: "Midnight Drive")
        await db.saveTracks(chapters + [music])

        await db.recordPlayed(channelId: "c", trackId: chapters[0].id, mediaKind: "audiobook")
        await db.recordPlayed(channelId: "c", trackId: chapters[1].id, mediaKind: "audiobook")
        await db.recordPlayed(channelId: "c", trackId: music.id, mediaKind: "music")

        let works = await db.fetchRecentlyPlayedWorks(limit: 10)

        let books = works.filter { $0.playsWholeWork }
        let tracks = works.filter { !$0.playsWholeWork }
        XCTAssertEqual(books.count, 1, "two book chapters collapse into one work")
        XCTAssertEqual(books.first?.workIdentifier, "bk")
        XCTAssertEqual(books.first?.mediaKind, .audiobook)
        XCTAssertEqual(books.first?.displayTitle, "Gallipoli")
        XCTAssertEqual(tracks.count, 1, "music stays one entry per track")
        XCTAssertEqual(tracks.first?.track.id, "song-1")
        XCTAssertFalse(tracks.first?.playsWholeWork ?? true)
    }

    func testMediaKindRoundTrips() async throws {
        let t = Track.makeStub(id: "p/ch_1.mp3", title: "Ch 1", parentIdentifier: "p")
        await db.saveTracks([t])
        await db.recordPlayed(channelId: "c", trackId: t.id, mediaKind: "lecture")

        let works = await db.fetchRecentlyPlayedWorks(limit: 10)
        XCTAssertEqual(works.count, 1)
        XCTAssertEqual(works.first?.mediaKind, .lecture)
        XCTAssertTrue(works.first?.playsWholeWork ?? false)
    }

    func testLegacyNullMediaKindDoesNotCollapseAsMusic() async throws {
        // A pre-migration row (no media_kind) with a parent but no spoken stamp
        // is treated as music and stays per-track — never mislabeled spoken.
        let a = Track.makeStub(id: "alb/t1.mp3", title: "Song A", parentIdentifier: "alb")
        let b = Track.makeStub(id: "alb/t2.mp3", title: "Song B", parentIdentifier: "alb")
        await db.saveTracks([a, b])
        await db.recordPlayed(channelId: "c", trackId: a.id)  // nil media_kind
        await db.recordPlayed(channelId: "c", trackId: b.id)

        let works = await db.fetchRecentlyPlayedWorks(limit: 10)
        XCTAssertEqual(works.count, 2, "music album tracks stay individual without a spoken kind")
        XCTAssertTrue(works.allSatisfy { !$0.playsWholeWork })
    }
}
