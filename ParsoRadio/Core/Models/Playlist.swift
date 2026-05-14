import Foundation

struct Playlist: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var isFavorites: Bool

    static func new(name: String, isFavorites: Bool = false) -> Playlist {
        Playlist(
            id: UUID().uuidString,
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            isFavorites: isFavorites
        )
    }
}
