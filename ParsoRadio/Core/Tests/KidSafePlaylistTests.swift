import XCTest
@testable import ParsoMusic

/// Phase: per-playlist parental "kid safe" flag. Default-deny — a playlist must
/// be EXPLICITLY marked kid-safe before it appears in Kids Mode.
final class KidSafePlaylistTests: XCTestCase {
    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    func test_newPlaylistDefaultsToNotKidSafe() async throws {
        let pl = try await db.createPlaylist(name: "Fresh")
        XCTAssertFalse(pl.isKidSafe,
            "playlists must default to NOT kid-safe — parents opt-in")
    }

    func test_setKidSafePersistsAndRoundTrips() async throws {
        let pl = try await db.createPlaylist(name: "Persist")
        await db.setPlaylistKidSafe(id: pl.id, isKidSafe: true)
        let loaded = await db.fetchPlaylists()
        XCTAssertEqual(loaded.first(where: { $0.id == pl.id })?.isKidSafe, true)
    }

    func test_setKidSafeCanBeReverted() async throws {
        let pl = try await db.createPlaylist(name: "Revert")
        await db.setPlaylistKidSafe(id: pl.id, isKidSafe: true)
        await db.setPlaylistKidSafe(id: pl.id, isKidSafe: false)
        let loaded = await db.fetchPlaylists()
        XCTAssertEqual(loaded.first(where: { $0.id == pl.id })?.isKidSafe, false)
    }

    func test_kidSafeFilterIsolatesMarkedPlaylists() async throws {
        let a = try await db.createPlaylist(name: "Songs for Kids")
        _ = try await db.createPlaylist(name: "Adult Mix")
        let c = try await db.createPlaylist(name: "Stories")
        await db.setPlaylistKidSafe(id: a.id, isKidSafe: true)
        await db.setPlaylistKidSafe(id: c.id, isKidSafe: true)
        let all = await db.fetchPlaylists()
        let kidSafeIds = Set(all.filter(\.isKidSafe).map(\.id))
        XCTAssertEqual(kidSafeIds, [a.id, c.id],
            "only explicitly-marked playlists must appear in the kid-safe set")
    }
}
