import Foundation

@MainActor
final class PlaylistViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var currentPlaylistTracks: [Track] = []
    @Published var trackCounts: [String: Int] = [:]

    let db: DatabaseService
    private var trackFavoriteCache: [String: Bool] = [:]

    init(db: DatabaseService) { self.db = db }

    var favoritesPlaylist: Playlist? { playlists.first { $0.isFavorites } }

    func loadPlaylists() async {
        playlists = await db.fetchPlaylists()
        for playlist in playlists {
            let tracks = await db.fetchTracks(forPlaylist: playlist.id)
            trackCounts[playlist.id] = tracks.count
        }
    }

    func trackCount(for playlist: Playlist) -> Int {
        trackCounts[playlist.id] ?? 0
    }

    @discardableResult
    func createPlaylist(name: String) async -> Playlist {
        let p = try! await db.createPlaylist(name: name)
        await loadPlaylists()
        return p
    }

    func renamePlaylist(_ playlist: Playlist, to name: String) async {
        guard !playlist.isFavorites else { return }
        await db.renamePlaylist(id: playlist.id, name: name)
        await loadPlaylists()
    }

    func deletePlaylist(_ playlist: Playlist) async {
        guard !playlist.isFavorites else { return }
        await db.deletePlaylist(id: playlist.id)
        await loadPlaylists()
    }

    // Persist a user-defined order for the non-Favorites playlists.
    func reorderPlaylists(_ ordered: [Playlist]) async {
        await db.setPlaylistOrder(ordered.map(\.id))
        await loadPlaylists()
    }

    func addTrack(_ track: Track, to playlist: Playlist) async {
        await db.addTrack(track, toPlaylist: playlist.id)
        if playlist.isFavorites { trackFavoriteCache[track.id] = true }
        trackCounts[playlist.id] = (trackCounts[playlist.id] ?? 0) + 1
    }

    // Bulk-add every part of a book/album. db.addTrack is INSERT OR IGNORE
    // (idempotent), so the count is re-derived from the DB rather than
    // incremented blindly — re-adding a partially-present book stays accurate.
    func addTracks(_ tracks: [Track], to playlist: Playlist) async {
        // Order-preserving bulk insert so a book/album reads in chapter order
        // (fetchTracks(forPlaylist:) sorts newest-first).
        await db.addTracksOrdered(tracks, toPlaylist: playlist.id)
        if playlist.isFavorites {
            tracks.forEach { trackFavoriteCache[$0.id] = true }
        }
        let updated = await db.fetchTracks(forPlaylist: playlist.id)
        trackCounts[playlist.id] = updated.count
    }

    func removeTrack(_ track: Track, from playlist: Playlist) async {
        await db.removeTrack(trackId: track.id, fromPlaylist: playlist.id)
        if playlist.isFavorites { trackFavoriteCache[track.id] = false }
        if let count = trackCounts[playlist.id], count > 0 {
            trackCounts[playlist.id] = count - 1
        }
    }

    func loadTracks(for playlist: Playlist) async {
        currentPlaylistTracks = await db.fetchTracks(forPlaylist: playlist.id)
        trackCounts[playlist.id] = currentPlaylistTracks.count
    }

    func reorderTracks(_ ordered: [Track], inPlaylist playlist: Playlist) async {
        // Optimistic: currentPlaylistTracks is already reordered by the caller
        await db.setTrackOrder(ordered.map(\.id), inPlaylist: playlist.id)
    }

    func isInFavorites(_ track: Track) async -> Bool {
        if let cached = trackFavoriteCache[track.id] { return cached }
        guard let fav = favoritesPlaylist else { return false }
        let result = await db.isTrack(track.id, inPlaylist: fav.id)
        trackFavoriteCache[track.id] = result
        return result
    }

    func isTrackInPlaylist(_ track: Track, playlist: Playlist) async -> Bool {
        await db.isTrack(track.id, inPlaylist: playlist.id)
    }

    func toggleFavorite(_ track: Track) async {
        guard let fav = favoritesPlaylist else { return }
        if await isInFavorites(track) {
            await removeTrack(track, from: fav)
        } else {
            await addTrack(track, to: fav)
        }
    }
}
