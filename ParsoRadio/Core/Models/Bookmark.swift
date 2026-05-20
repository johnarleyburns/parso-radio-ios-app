import Foundation

/// A within-track timestamp the user has marked. Distinct from
/// `PlaybackPosition` (one-per-channel/playlist auto-resume) — bookmarks are
/// many-per-track, user-named, and survive channel switches.
struct Bookmark: Identifiable, Equatable, Hashable {
    let id: String
    let trackId: String
    let positionSeconds: Double
    let label: String?
    let createdAt: Date

    static func new(trackId: String,
                    positionSeconds: Double,
                    label: String? = nil,
                    createdAt: Date = Date()) -> Bookmark {
        Bookmark(
            id: UUID().uuidString,
            trackId: trackId,
            positionSeconds: max(0, positionSeconds),
            label: label?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            createdAt: createdAt
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
