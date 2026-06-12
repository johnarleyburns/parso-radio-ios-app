import XCTest
@testable import ParsoMusic

@MainActor
final class PlaylistViewModelTests: XCTestCase {
    private var db: DatabaseService!
    private var vm: PlaylistViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        vm = PlaylistViewModel(db: db)
    }

    func testLoadPlaylistsIncludesFavorites() async throws {
        await vm.loadPlaylists()
        XCTAssertTrue(vm.playlists.contains { $0.isFavorites }, "Favorites playlist must be present after loadPlaylists()")
        XCTAssertNotNil(vm.favoritesPlaylist, "favoritesPlaylist (tracks) must be non-nil")
        XCTAssertNotNil(vm.favoriteAlbumsPlaylist, "favoriteAlbumsPlaylist must be non-nil")
        XCTAssertNotNil(vm.favoriteBooksPlaylist, "favoriteBooksPlaylist must be non-nil")
        XCTAssertEqual(vm.favoritesPlaylist?.name, "Favorite Tracks")
        XCTAssertEqual(vm.favoriteAlbumsPlaylist?.name, "Favorite Albums")
        XCTAssertEqual(vm.favoriteBooksPlaylist?.name, "Favorite Books")
        XCTAssertEqual(vm.favoritesPlaylist?.type, .tracks)
        XCTAssertEqual(vm.favoriteAlbumsPlaylist?.type, .album)
        XCTAssertEqual(vm.favoriteBooksPlaylist?.type, .book)
    }

    func testCreatePlaylistAppearsAfterLoad() async throws {
        await vm.createPlaylist(name: "Rock Hits")
        XCTAssertTrue(vm.playlists.contains { $0.name == "Rock Hits" })
    }

    func testDeletePlaylistRemovedFromPublished() async throws {
        await vm.createPlaylist(name: "Temp Mix")
        guard let playlist = vm.playlists.first(where: { $0.name == "Temp Mix" }) else {
            XCTFail("Playlist not found after creation"); return
        }
        await vm.deletePlaylist(playlist)
        XCTAssertFalse(vm.playlists.contains { $0.id == playlist.id })
    }

    func testDeleteFavoritesPlaylistIsNoop() async throws {
        await vm.loadPlaylists()
        guard let fav = vm.favoritesPlaylist else { XCTFail("No favorites"); return }
        let beforeCount = vm.playlists.count
        await vm.deletePlaylist(fav)
        XCTAssertEqual(vm.playlists.count, beforeCount, "Deleting Favorites must be a no-op")
    }

    func testRenamePlaylist() async throws {
        await vm.createPlaylist(name: "Before")
        guard let playlist = vm.playlists.first(where: { $0.name == "Before" }) else {
            XCTFail("Playlist not found"); return
        }
        await vm.renamePlaylist(playlist, to: "After")
        XCTAssertTrue(vm.playlists.contains { $0.name == "After" })
        XCTAssertFalse(vm.playlists.contains { $0.name == "Before" })
    }

    func testAddAndRemoveTrack() async throws {
        await vm.createPlaylist(name: "My Tracks")
        guard let playlist = vm.playlists.first(where: { $0.name == "My Tracks" }) else {
            XCTFail("Playlist not found"); return
        }
        let track = makeTrack(id: "vm-trk-1")

        await vm.addTrack(track, to: playlist)
        await vm.loadTracks(for: playlist)
        XCTAssertTrue(vm.currentPlaylistTracks.contains { $0.id == "vm-trk-1" })

        await vm.removeTrack(track, from: playlist)
        await vm.loadTracks(for: playlist)
        XCTAssertFalse(vm.currentPlaylistTracks.contains { $0.id == "vm-trk-1" })
    }

    func testTrackCountUpdatedOnAdd() async throws {
        await vm.createPlaylist(name: "Counted")
        guard let playlist = vm.playlists.first(where: { $0.name == "Counted" }) else {
            XCTFail("Playlist not found"); return
        }
        XCTAssertEqual(vm.trackCount(for: playlist), 0)

        let track = makeTrack(id: "vm-cnt-1")
        await vm.addTrack(track, to: playlist)
        XCTAssertEqual(vm.trackCount(for: playlist), 1)
    }

    func testIsInFavoritesAndToggleFavorite() async throws {
        await vm.loadPlaylists()
        let track = makeTrack(id: "vm-fav-1")
        await db.saveTracks([track])

        let before = await vm.isInFavorites(track)
        XCTAssertFalse(before)

        await vm.toggleFavorite(track)
        let after = await vm.isInFavorites(track)
        XCTAssertTrue(after)

        // toggle again → remove from favorites
        await vm.toggleFavorite(track)
        let final = await vm.isInFavorites(track)
        XCTAssertFalse(final)
    }

    func testIsTrackInPlaylist() async throws {
        await vm.createPlaylist(name: "CheckMembership")
        guard let playlist = vm.playlists.first(where: { $0.name == "CheckMembership" }) else {
            XCTFail("Playlist not found"); return
        }
        let track = makeTrack(id: "vm-mem-1")

        let before = await vm.isTrackInPlaylist(track, playlist: playlist)
        XCTAssertFalse(before)

        await vm.addTrack(track, to: playlist)
        let after = await vm.isTrackInPlaylist(track, playlist: playlist)
        XCTAssertTrue(after)
    }

    // Bulk-add (whole book/album). INSERT OR IGNORE is idempotent, so re-adding
    // an overlapping set must not inflate the count.
    func testAddTracksBulkIsIdempotent() async throws {
        await vm.createPlaylist(name: "Whole Book")
        guard let pl = vm.playlists.first(where: { $0.name == "Whole Book" }) else {
            XCTFail("Playlist not found"); return
        }
        let parts = (1...5).map { makeTrack(id: "bk/part\($0)") }

        await vm.addTracks(parts, to: pl)
        await vm.loadTracks(for: pl)
        XCTAssertEqual(vm.currentPlaylistTracks.count, 5, "all 5 parts added")
        XCTAssertEqual(vm.trackCount(for: pl), 5, "count reflects the bulk add")

        // Re-add the same set plus one new part — only the new one counts.
        await vm.addTracks(parts + [makeTrack(id: "bk/part6")], to: pl)
        await vm.loadTracks(for: pl)
        XCTAssertEqual(vm.currentPlaylistTracks.count, 6,
            "re-adding existing parts must not duplicate rows (idempotent)")
        XCTAssertEqual(vm.trackCount(for: pl), 6,
            "count must be re-derived from the DB, not blindly incremented")
    }

    // Item 2: reordering persists and survives a reload (Favorites pinned).
    func testReorderPlaylistsPersists() async throws {
        await vm.createPlaylist(name: "One")
        await vm.createPlaylist(name: "Two")
        await vm.createPlaylist(name: "Three")
        await vm.loadPlaylists()

        let others = vm.playlists.filter { !$0.isFavorites }
        XCTAssertEqual(others.map(\.name), ["One", "Two", "Three"])

        // Move "Three" to the front of the non-favorites.
        let reordered = [others[2], others[0], others[1]]
        await vm.reorderPlaylists(reordered)

        XCTAssertTrue(vm.playlists.first?.isFavorites ?? false,
            "Favorites stays pinned first")
        XCTAssertEqual(vm.playlists.filter { !$0.isFavorites }.map(\.name),
                       ["Three", "One", "Two"],
            "reorderPlaylists must persist the new order")
    }

    func testIsInFavoriteAlbumsAndToggle() async throws {
        await vm.loadPlaylists()
        let track = makeTrack(id: "vm-alb-trk-1", parentIdentifier: "album-abc")
        await db.saveTracks([track])

        let before = await vm.isInFavoriteAlbums(track)
        XCTAssertFalse(before)

        await vm.toggleFavoriteAlbum(track)
        let after = await vm.isInFavoriteAlbums(track)
        XCTAssertTrue(after)

        // toggle again → remove
        await vm.toggleFavoriteAlbum(track)
        let final = await vm.isInFavoriteAlbums(track)
        XCTAssertFalse(final)
    }

    func testIsInFavoriteBooksAndToggle() async throws {
        await vm.loadPlaylists()
        let track = makeTrack(id: "vm-bk-trk-1", parentIdentifier: "book-abc")
        await db.saveTracks([track])

        let before = await vm.isInFavoriteBooks(track)
        XCTAssertFalse(before)

        await vm.toggleFavoriteBook(track)
        let after = await vm.isInFavoriteBooks(track)
        XCTAssertTrue(after)

        // toggle again → remove
        await vm.toggleFavoriteBook(track)
        let final = await vm.isInFavoriteBooks(track)
        XCTAssertFalse(final)
    }

    func testAlbumFavoriteUsesParentIdentifier() async throws {
        await vm.loadPlaylists()
        let t1 = makeTrack(id: "vm-alb-p1", parentIdentifier: "album-xyz", partNumber: 1)
        let t2 = makeTrack(id: "vm-alb-p2", parentIdentifier: "album-xyz", partNumber: 2)
        await db.saveTracks([t1, t2])

        // Neither is favorited yet
        var f1 = await vm.isInFavoriteAlbums(t1)
        var f2 = await vm.isInFavoriteAlbums(t2)
        XCTAssertFalse(f1)
        XCTAssertFalse(f2)

        // Favorite t1 → both report favorited (same parent)
        await vm.toggleFavoriteAlbum(t1)
        f1 = await vm.isInFavoriteAlbums(t1)
        f2 = await vm.isInFavoriteAlbums(t2)
        XCTAssertTrue(f1)
        XCTAssertTrue(f2)

        // Unfavorite via t2 → both unfavorited
        await vm.toggleFavoriteAlbum(t2)
        f1 = await vm.isInFavoriteAlbums(t1)
        f2 = await vm.isInFavoriteAlbums(t2)
        XCTAssertFalse(f1)
        XCTAssertFalse(f2)
    }

    func testTrackFavoriteAndAlbumFavoriteIndependent() async throws {
        await vm.loadPlaylists()
        let track = makeTrack(id: "vm-ind-1", parentIdentifier: "album-ind")
        await db.saveTracks([track])

        // Not in either
        var inFav = await vm.isInFavorites(track)
        var inAlb = await vm.isInFavoriteAlbums(track)
        XCTAssertFalse(inFav)
        XCTAssertFalse(inAlb)

        // Favorite track only
        await vm.toggleFavorite(track)
        inFav = await vm.isInFavorites(track)
        inAlb = await vm.isInFavoriteAlbums(track)
        XCTAssertTrue(inFav)
        XCTAssertFalse(inAlb)

        // Favorite album too
        await vm.toggleFavoriteAlbum(track)
        inFav = await vm.isInFavorites(track)
        inAlb = await vm.isInFavoriteAlbums(track)
        XCTAssertTrue(inFav)
        XCTAssertTrue(inAlb)

        // Unfavorite track only
        await vm.toggleFavorite(track)
        inFav = await vm.isInFavorites(track)
        inAlb = await vm.isInFavoriteAlbums(track)
        XCTAssertFalse(inFav)
        XCTAssertTrue(inAlb)
    }

    // MARK: - Helpers

    private func makeTrack(id: String, parentIdentifier: String? = nil,
                           partNumber: Int? = nil) -> Track {
        Track(
            id: id, source: "internet_archive",
            title: "VM Test Track", artist: "Test Artist",
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 0.75,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0,
            partNumber: partNumber,
            totalParts: partNumber != nil ? 2 : nil,
            parentIdentifier: parentIdentifier
        )
    }
}
