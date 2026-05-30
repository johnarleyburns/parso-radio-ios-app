import Foundation

struct Playlist: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var isFavorites: Bool
    // Parental flag: when true, this playlist is visible (and read-only) inside
    // Kids Mode. Unchecked by default — parents opt-in per playlist.
    var isKidSafe: Bool = false

    static func new(name: String, isFavorites: Bool = false,
                    isKidSafe: Bool = false) -> Playlist {
        Playlist(
            id: UUID().uuidString,
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            isFavorites: isFavorites,
            isKidSafe: isKidSafe
        )
    }
}
