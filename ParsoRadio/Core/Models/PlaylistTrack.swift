import Foundation

struct PlaylistTrack: Codable, Identifiable {
    let id: String
    let playlistId: String
    let trackId: String
    var sortOrder: Int
    let addedAt: Date
}
