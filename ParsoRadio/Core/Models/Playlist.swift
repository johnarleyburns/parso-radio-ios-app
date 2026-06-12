import Foundation

enum PlaylistType: String, Codable, CaseIterable {
    case tracks
    case album
    case book
}

struct Playlist: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var isFavorites: Bool
    var type: PlaylistType = .tracks
    // Parental flag: when true, this playlist is visible (and read-only) inside
    // Kids Mode. Unchecked by default — parents opt-in per playlist.
    var isKidSafe: Bool = false

    static func new(name: String, isFavorites: Bool = false,
                    type: PlaylistType = .tracks,
                    isKidSafe: Bool = false) -> Playlist {
        Playlist(
            id: UUID().uuidString,
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            isFavorites: isFavorites,
            type: type,
            isKidSafe: isKidSafe
        )
    }
}

extension Playlist {
    var isAlbumFavorites: Bool { isFavorites && type == .album }
    var isBookFavorites: Bool { isFavorites && type == .book }
    var isTrackFavorites: Bool { isFavorites && type == .tracks }
    var isBuiltin: Bool { isFavorites }
}
