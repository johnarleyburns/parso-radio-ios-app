import XCTest
@testable import ParsoMusic

/// Regression for the critical "playlist reversed after reordering" bug:
/// setTrackOrder wrote ascending sort_order while fetchTracks reads DESC,
/// so every reorder flipped the list. These lock the round-trip contract.
final class PlaylistOrderTests: XCTestCase {

    private var db: DatabaseService!
    private var playlistId: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    private func makeTrack(_ id: String) -> Track {
        Track(
            id: id, source: "internet_archive",
            title: id, artist: "A",
            duration: 100,
            streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1.0,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0
        )
    }

    private func newPlaylist() async throws -> Playlist {
        try await db.createPlaylist(name: "Book")
    }

    func testAddedBookOrderIsPreserved() async throws {
        let pl = try await newPlaylist()
        let chapters = (1...5).map { makeTrack("ch-\($0)") }
        await db.addTracksOrdered(chapters, toPlaylist: pl.id)
        let fetched = await db.fetchTracks(forPlaylist: pl.id).map(\.id)
        XCTAssertEqual(fetched, ["ch-1", "ch-2", "ch-3", "ch-4", "ch-5"],
            "A book added in chapter order must read back in chapter order.")
    }

    func testReorderPreservesNewOrderNotReversed() async throws {
        let pl = try await newPlaylist()
        let chapters = (1...4).map { makeTrack("ch-\($0)") }
        await db.addTracksOrdered(chapters, toPlaylist: pl.id)

        // User drags into a new explicit order.
        let newOrder = ["ch-3", "ch-1", "ch-4", "ch-2"]
        await db.setTrackOrder(newOrder, inPlaylist: pl.id)

        let fetched = await db.fetchTracks(forPlaylist: pl.id).map(\.id)
        XCTAssertEqual(fetched, newOrder,
            "setTrackOrder must persist EXACTLY the order given — not reversed.")
    }

    func testReorderToSameOrderIsStable() async throws {
        let pl = try await newPlaylist()
        let chapters = (1...3).map { makeTrack("ch-\($0)") }
        await db.addTracksOrdered(chapters, toPlaylist: pl.id)
        let order = ["ch-1", "ch-2", "ch-3"]
        // Re-applying the existing order must not flip it (the original bug).
        await db.setTrackOrder(order, inPlaylist: pl.id)
        let fetched = await db.fetchTracks(forPlaylist: pl.id).map(\.id)
        XCTAssertEqual(fetched, order)
    }
}
