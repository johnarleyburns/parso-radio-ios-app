import XCTest
@testable import ParsoMusic

/// Issue #3 / foundation: `fetchRecentlyPlayedWorks` collapses every multi-part
/// work — book/lecture/podcast chapters AND music album tracks — under their
/// shared parent identifier (one card per work), while a standalone track with
/// no parent stays its own card. Uses the persisted media kind.
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

    func testMusicAlbumTracksCollapseIntoOneWork() async throws {
        // Album tracks sharing a parent identifier collapse into a single music
        // work card, held at the most-recently-played track's position, even
        // when the (legacy) media_kind is null and falls back to .music.
        let a = Track.makeStub(id: "alb/t1.mp3", title: "Song A", parentIdentifier: "alb")
        let b = Track.makeStub(id: "alb/t2.mp3", title: "Song B", parentIdentifier: "alb")
        await db.saveTracks([a, b])
        await db.recordPlayed(channelId: "c", trackId: a.id)  // nil media_kind
        await db.recordPlayed(channelId: "c", trackId: b.id)

        let works = await db.fetchRecentlyPlayedWorks(limit: 10)
        XCTAssertEqual(works.count, 1, "music album tracks collapse into one work")
        let album = works.first
        XCTAssertEqual(album?.mediaKind, .music)
        XCTAssertTrue(album?.playsWholeWork ?? false)
        XCTAssertEqual(album?.workIdentifier, "alb")
        XCTAssertEqual(album?.track.id, b.id, "the most-recently-played track represents the album")
    }

    func testStandaloneTrackStaysPerCard() async throws {
        // A track with no parent identifier cannot collapse — it stays its own
        // card regardless of media kind.
        let single = Track.makeStub(id: "single-1", title: "Lonely Single")
        await db.saveTracks([single])
        await db.recordPlayed(channelId: "c", trackId: single.id, mediaKind: "music")

        let works = await db.fetchRecentlyPlayedWorks(limit: 10)
        XCTAssertEqual(works.count, 1)
        XCTAssertFalse(works.first?.playsWholeWork ?? true)
        XCTAssertEqual(works.first?.track.id, "single-1")
    }
}
