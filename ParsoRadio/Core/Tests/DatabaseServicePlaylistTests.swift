import XCTest
@testable import ParsoMusic

final class DatabaseServicePlaylistTests: XCTestCase {
    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    // MARK: - Playlist CRUD

    func testCreateAndFetchPlaylist() async throws {
        let playlist = try await db.createPlaylist(name: "My Mix")
        XCTAssertEqual(playlist.name, "My Mix")
        XCTAssertFalse(playlist.isFavorites)

        let all = await db.fetchPlaylists()
        XCTAssertTrue(all.contains { $0.name == "My Mix" })
    }

    func testFavoritesPlaylistSeededAtCreation() async throws {
        let all = await db.fetchPlaylists()
        XCTAssertTrue(all.contains { $0.isFavorites }, "Favorites playlist must be seeded on first schema creation")
    }

    // Item 2: persisted custom playlist order. Favorites stays pinned first
    // (isFavorites DESC); setPlaylistOrder controls the rest.
    func testPlaylistCustomOrderPersists() async throws {
        let a = try await db.createPlaylist(name: "Alpha")
        let b = try await db.createPlaylist(name: "Bravo")
        let c = try await db.createPlaylist(name: "Charlie")

        // Default: Favorites first, then creation order.
        var all = await db.fetchPlaylists()
        XCTAssertTrue(all.first?.isFavorites ?? false, "Favorites pinned first")
        XCTAssertEqual(all.filter { !$0.isFavorites }.map(\.name),
                       ["Alpha", "Bravo", "Charlie"])

        // Reorder the non-favorites: Charlie, Alpha, Bravo.
        await db.setPlaylistOrder([c.id, a.id, b.id])
        all = await db.fetchPlaylists()
        XCTAssertTrue(all.first?.isFavorites ?? false,
            "Favorites must remain pinned first after reorder")
        XCTAssertEqual(all.filter { !$0.isFavorites }.map(\.name),
                       ["Charlie", "Alpha", "Bravo"],
            "custom order must persist via setPlaylistOrder")
    }

    // Item 4/8a: a whole book/album must read in the given order even though
    // the playlist fetch is newest-first (sort_order DESC).
    func testAddTracksOrderedReadsInGivenOrder() async throws {
        let pl = try await db.createPlaylist(name: "Book Shelf")
        let parts = (1...5).map { i -> Track in
            Track(id: "bk/part\(i).mp3", source: "internet_archive",
                  title: "Ch \(i)", artist: "Author", duration: 60,
                  streamURL: URL(string: "https://archive.org/download/bk/part\(i).mp3")!,
                  downloadURL: nil, localFilePath: nil, license: .publicDomain,
                  tags: [], qualityScore: 0.7, rawCreator: "", composer: nil,
                  instruments: [], metadataConfidence: 1.0,
                  partNumber: i, totalParts: 5, parentIdentifier: "bk")
        }
        await db.addTracksOrdered(parts, toPlaylist: pl.id)
        let got = await db.fetchTracks(forPlaylist: pl.id)
        XCTAssertEqual(got.map(\.id), parts.map(\.id),
            "addTracksOrdered must preserve chapter order under DESC fetch")
    }

    // Item 4: re-probe purge — stale parent rows must be removable so a
    // mixed-format extraction can be replaced by a clean single-format set.
    func testDeleteTracksForParentIdentifier() async throws {
        let mixed = ["bk/c1.mp3", "bk/c1.ogg", "bk/c2.mp3", "other/x.mp3"].map { id in
            Track(id: id, source: "internet_archive", title: id, artist: "a",
                  duration: 1, streamURL: URL(string: "https://archive.org/download/\(id)")!,
                  downloadURL: nil, localFilePath: nil, license: .publicDomain,
                  tags: [], qualityScore: 0.7, rawCreator: "", composer: nil,
                  instruments: [], metadataConfidence: 1.0,
                  partNumber: 1, totalParts: 1,
                  parentIdentifier: id.hasPrefix("bk/") ? "bk" : "other")
        }
        await db.saveTracks(mixed)
        await db.deleteTracks(forParentIdentifier: "bk")
        let bk = await db.fetchTracks(forParentIdentifier: "bk")
        let other = await db.fetchTracks(forParentIdentifier: "other")
        XCTAssertTrue(bk.isEmpty, "all 'bk' parts purged")
        XCTAssertEqual(other.count, 1, "other items untouched")
    }

    func testRenamePlaylist() async throws {
        let playlist = try await db.createPlaylist(name: "Old Name")
        await db.renamePlaylist(id: playlist.id, name: "New Name")

        let all = await db.fetchPlaylists()
        XCTAssertTrue(all.contains { $0.name == "New Name" })
        XCTAssertFalse(all.contains { $0.name == "Old Name" })
    }

    func testDeletePlaylist() async throws {
        let playlist = try await db.createPlaylist(name: "Temp")
        await db.deletePlaylist(id: playlist.id)

        let all = await db.fetchPlaylists()
        XCTAssertFalse(all.contains { $0.id == playlist.id })
    }

    // MARK: - Playlist tracks

    func testAddAndFetchTracksForPlaylist() async throws {
        let playlist = try await db.createPlaylist(name: "Test Playlist")
        let track = makeTrack(id: "trk-1")
        await db.addTrack(track, toPlaylist: playlist.id)

        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].id, "trk-1")
    }

    func testRemoveTrackFromPlaylist() async throws {
        let playlist = try await db.createPlaylist(name: "Test")
        let track = makeTrack(id: "trk-2")
        await db.addTrack(track, toPlaylist: playlist.id)
        await db.removeTrack(trackId: track.id, fromPlaylist: playlist.id)

        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        XCTAssertTrue(tracks.isEmpty)
    }

    func testIsTrackInPlaylist() async throws {
        let playlist = try await db.createPlaylist(name: "Check")
        let track = makeTrack(id: "trk-3")
        await db.saveTracks([track])

        let before = await db.isTrack(track.id, inPlaylist: playlist.id)
        XCTAssertFalse(before)

        await db.addTrack(track, toPlaylist: playlist.id)
        let after = await db.isTrack(track.id, inPlaylist: playlist.id)
        XCTAssertTrue(after)
    }

    func testAddTrackIsIdempotent() async throws {
        let playlist = try await db.createPlaylist(name: "Idempotent")
        let track = makeTrack(id: "trk-idem")
        await db.addTrack(track, toPlaylist: playlist.id)
        await db.addTrack(track, toPlaylist: playlist.id)  // second add should be ignored

        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        XCTAssertEqual(tracks.count, 1)
    }

    func testTrackOrderPreservedInFetch() async throws {
        let playlist = try await db.createPlaylist(name: "Ordered")
        let t1 = makeTrack(id: "ord-1")
        let t2 = makeTrack(id: "ord-2")
        let t3 = makeTrack(id: "ord-3")
        // Add in order; the DB assigns ascending sortOrder automatically
        await db.addTrack(t1, toPlaylist: playlist.id)
        await db.addTrack(t2, toPlaylist: playlist.id)
        await db.addTrack(t3, toPlaylist: playlist.id)

        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        XCTAssertEqual(tracks.count, 3)
        // fetchTracks orders by sort_order DESC, so last added appears first
        XCTAssertEqual(tracks.map { $0.id }, ["ord-3", "ord-2", "ord-1"])
    }

    func testSetTrackOrder() async throws {
        let playlist = try await db.createPlaylist(name: "ReorderTest")
        let t1 = makeTrack(id: "ro-1")
        let t2 = makeTrack(id: "ro-2")
        await db.addTrack(t1, toPlaylist: playlist.id)
        await db.addTrack(t2, toPlaylist: playlist.id)

        // Reverse order: ro-2 first, ro-1 second (index 0 < 1, DESC gives ro-1 first after setTrackOrder)
        await db.setTrackOrder(["ro-2", "ro-1"], inPlaylist: playlist.id)
        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        // sort_order 0 for ro-2, 1 for ro-1 → DESC gives ro-1 first
        XCTAssertEqual(tracks[0].id, "ro-1")
        XCTAssertEqual(tracks[1].id, "ro-2")
    }

    // MARK: - Play history

    func testRecordPlayedAndRecentlyHeardIds() async throws {
        let channel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
        let t1 = makeTrack(id: "hist-1", composer: "bach")
        let t2 = makeTrack(id: "hist-2", composer: "bach")
        await db.saveTracks([t1, t2])

        await db.recordPlayed(channelId: channel.id, trackId: t1.id)
        await db.recordPlayed(channelId: channel.id, trackId: t2.id)

        let heard = await db.recentlyHeardIds(forChannel: channel.id, withinDays: 30)
        XCTAssertTrue(heard.contains("hist-1"))
        XCTAssertTrue(heard.contains("hist-2"))
    }

    func testEvictOldPlayHistoryDoesNotCrash() async throws {
        await db.evictOldPlayHistory(olderThanDays: 30)
    }

    func testLastPlayedTrack() async throws {
        let channel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
        let track = makeTrack(id: "last-1", composer: "bach")
        await db.saveTracks([track])
        await db.recordPlayed(channelId: channel.id, trackId: track.id)

        let last = await db.lastPlayedTrack(forChannel: channel.id)
        XCTAssertEqual(last?.id, "last-1")
    }

    func testRecentlyHeardIdsExcludesOtherChannels() async throws {
        let bachChannel  = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
        let chopinChannel = Channel(id: "chopin", name: "Chopin", category: "Classical", icon: "pianokeys", composers: ["chopin"], preferredSource: "internet_archive")
        let t1 = makeTrack(id: "cross-1", composer: "bach")
        let t2 = makeTrack(id: "cross-2", composer: "chopin")
        await db.saveTracks([t1, t2])
        await db.recordPlayed(channelId: bachChannel.id, trackId: t1.id)
        await db.recordPlayed(channelId: chopinChannel.id, trackId: t2.id)

        let bachHeard = await db.recentlyHeardIds(forChannel: bachChannel.id)
        XCTAssertTrue(bachHeard.contains("cross-1"))
        XCTAssertFalse(bachHeard.contains("cross-2"))
    }

    // MARK: - Helpers

    private func makeTrack(id: String, composer: String? = nil) -> Track {
        Track(
            id: id, source: "internet_archive",
            title: "Test Track", artist: "Test Artist",
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 0.75,
            rawCreator: composer ?? "",
            composer: composer,
            instruments: ["strings"],
            metadataConfidence: 3.0
        )
    }
}
