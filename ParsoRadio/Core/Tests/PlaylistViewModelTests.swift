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

    // MARK: - Helpers

    private func makeTrack(id: String) -> Track {
        Track(
            id: id, source: "internet_archive",
            title: "VM Test Track", artist: "Test Artist",
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 0.75,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 2.0
        )
    }
}
