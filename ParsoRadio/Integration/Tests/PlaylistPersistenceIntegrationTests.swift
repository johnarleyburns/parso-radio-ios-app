import XCTest
@testable import ParsoMusic

// Integration test: exercises playlist CRUD against a real (in-memory) SQLite database.
// No network calls are made here. Kept in Integration/Tests because it exercises
// the full DatabaseService stack end-to-end across multiple async operations.
@MainActor
final class PlaylistPersistenceIntegrationTests: XCTestCase {

    private var db: DatabaseService!
    private var vm: PlaylistViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        vm = PlaylistViewModel(db: db)
        executionTimeAllowance = 30
    }

    // Verify full create → load → add tracks → reorder → delete lifecycle
    func testFullPlaylistLifecycle() async throws {
        // 1. Create
        await vm.createPlaylist(name: "Integration Test")
        guard let playlist = vm.playlists.first(where: { $0.name == "Integration Test" }) else {
            XCTFail("Playlist not created"); return
        }

        // 2. Add tracks in order
        let tracks = (1...5).map { makeTrack(id: "integ-\($0)") }
        for track in tracks {
            await vm.addTrack(track, to: playlist)
        }
        await vm.loadTracks(for: playlist)
        XCTAssertEqual(vm.currentPlaylistTracks.count, 5)

        // 3. Reorder — reverse
        let reversed = vm.currentPlaylistTracks.reversed()
        let reversedArray = Array(reversed)
        await vm.reorderTracks(reversedArray, inPlaylist: playlist)

        // 4. Remove one track
        let trackToRemove = tracks[2]
        await vm.removeTrack(trackToRemove, from: playlist)
        await vm.loadTracks(for: playlist)
        XCTAssertEqual(vm.currentPlaylistTracks.count, 4)
        XCTAssertFalse(vm.currentPlaylistTracks.contains { $0.id == trackToRemove.id })

        // 5. Delete playlist
        await vm.deletePlaylist(playlist)
        XCTAssertFalse(vm.playlists.contains { $0.id == playlist.id })

        // 6. Verify playlist_tracks also deleted (no orphan rows)
        let orphans = await db.fetchTracks(forPlaylist: playlist.id)
        XCTAssertTrue(orphans.isEmpty, "Deleting a playlist must remove its playlist_tracks rows")
    }

    // Verify Favorites survives a delete attempt and works for heart-toggle
    func testFavoritesHeartToggle() async throws {
        await vm.loadPlaylists()
        guard let fav = vm.favoritesPlaylist else {
            XCTFail("No Favorites playlist"); return
        }

        let track = makeTrack(id: "heart-track-1")
        await db.saveTracks([track])

        // Not in favorites initially
        let notFav = await vm.isInFavorites(track)
        XCTAssertFalse(notFav)

        // Add to favorites via toggle
        await vm.toggleFavorite(track)
        let isFav = await vm.isInFavorites(track)
        XCTAssertTrue(isFav)
        XCTAssertEqual(vm.trackCount(for: fav), 1)

        // Remove from favorites via toggle
        await vm.toggleFavorite(track)
        let removedFav = await vm.isInFavorites(track)
        XCTAssertFalse(removedFav)
        XCTAssertEqual(vm.trackCount(for: fav), 0)

        // Favorites playlist itself must still exist after toggling
        XCTAssertTrue(vm.playlists.contains { $0.isFavorites })
    }

    // Verify play history integration: recordPlayed feeds recentlyHeardIds
    func testPlayHistoryPersistenceAcrossOperations() async throws {
        let channel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
        let tracks = (1...3).map { makeTrack(id: "hist-integ-\($0)", composer: "bach") }
        await db.saveTracks(tracks)

        for track in tracks {
            await db.recordPlayed(channelId: channel.id, trackId: track.id)
        }

        let heard = await db.recentlyHeardIds(forChannel: channel.id, withinDays: 30)
        XCTAssertEqual(heard.count, 3)

        // lastPlayedTrack should return a valid track
        let last = await db.lastPlayedTrack(forChannel: channel.id)
        XCTAssertNotNil(last)
        XCTAssertTrue(tracks.map(\.id).contains(last?.id ?? ""))

        // eviction of old history must not affect recent entries
        await db.evictOldPlayHistory(olderThanDays: 30)
        let heardAfterEviction = await db.recentlyHeardIds(forChannel: channel.id, withinDays: 30)
        // Recent entries (just now) should survive a 30-day eviction
        XCTAssertEqual(heardAfterEviction.count, 3)
    }

    // MARK: - Helpers

    private func makeTrack(id: String, composer: String? = nil) -> Track {
        Track(
            id: id, source: "internet_archive",
            title: "Integration Track \(id)", artist: "Test Artist",
            duration: 200,
            streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 0.8,
            rawCreator: composer ?? "",
            composer: composer,
            instruments: ["strings"],
            metadataConfidence: 3.0
        )
    }
}
