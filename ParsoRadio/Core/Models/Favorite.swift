import Foundation

enum FavoriteKind: String, Codable, CaseIterable {
    case track
    case book
    case episode
    case lecture
}

struct Favorite: Codable, Identifiable {
    let id: String
    let kind: FavoriteKind
    let dateAdded: Date

    let title: String
    let creator: String?
    let artworkURL: URL?
    let sourceIdentifier: String

    var resumePoint: ResumePoint?
}

struct ResumePoint: Codable, Equatable {
    var chapterIndex: Int?
    var positionSeconds: Double
    var updatedAt: Date
}

extension Track {
    func favoriteID(for kind: FavoriteKind) -> String {
        switch kind {
        case .track:
            return id
        case .book:
            return parentIdentifier ?? id
        case .episode:
            return id
        case .lecture:
            return id
        }
    }
}

enum ContentTypeHint {
    case musicTrack
    case audiobook
    case podcastEpisode
    case lecture
}

extension Track {
    func resolveContentType(channel: Channel?) -> ContentTypeHint {
        if source == "podcast" { return .podcastEpisode }
        if source == "oxford_lectures" { return .lecture }
        if let cat = channel?.category,
           (cat == "Audiobooks" || cat == "Curated Books") {
            return .audiobook
        }
        if parentIdentifier != nil,
           channel?.contentType == .spokenWord {
            return .audiobook
        }
        return .musicTrack
    }

    func favoriteKind(channel: Channel?) -> FavoriteKind {
        switch resolveContentType(channel: channel) {
        case .musicTrack: return .track
        case .audiobook: return .book
        case .podcastEpisode: return .episode
        case .lecture: return .lecture
        }
    }
}
