import Foundation

enum FavoriteKind: String, Codable, CaseIterable {
    case track
    case book
    case episode
    case lecture

    init(mediaKind: MediaKind) {
        switch mediaKind {
        case .music, .ambient: self = .track
        case .audiobook: self = .book
        case .podcast: self = .episode
        case .lecture: self = .lecture
        }
    }
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
        switch mediaKind(in: channel) {
        case .music, .ambient: return .musicTrack
        case .audiobook: return .audiobook
        case .podcast: return .podcastEpisode
        case .lecture: return .lecture
        }
    }

    func favoriteKind(channel: Channel?) -> FavoriteKind {
        switch mediaKind(in: channel) {
        case .music, .ambient: return .track
        case .audiobook: return .book
        case .podcast: return .episode
        case .lecture: return .lecture
        }
    }
}
