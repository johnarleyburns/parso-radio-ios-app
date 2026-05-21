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
    /// `true` means this is the safety-net "last paused / switched" position
    /// the player auto-writes — distinct from user-created bookmarks. There is
    /// at most one autosave per track (deterministic id).
    var isAutosave: Bool = false

    static func new(trackId: String,
                    positionSeconds: Double,
                    label: String? = nil,
                    createdAt: Date = Date()) -> Bookmark {
        Bookmark(
            id: UUID().uuidString,
            trackId: trackId,
            positionSeconds: max(0, positionSeconds),
            label: label?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            createdAt: createdAt,
            isAutosave: false
        )
    }

    /// Deterministic id so insert-or-replace upserts a single autosave per
    /// track without a prior delete.
    static func autosaveId(forTrack trackId: String) -> String {
        "autosave:\(trackId)"
    }

    static func autosave(trackId: String, positionSeconds: Double,
                         createdAt: Date = Date()) -> Bookmark {
        Bookmark(
            id: autosaveId(forTrack: trackId),
            trackId: trackId,
            positionSeconds: max(0, positionSeconds),
            label: nil,
            createdAt: createdAt,
            isAutosave: true
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
