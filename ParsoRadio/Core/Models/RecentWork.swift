import Foundation

/// One entry in the "Jump back in" shelf. A `RecentWork` is either a single
/// music track (`playsWholeWork == false`) or a whole spoken work — audiobook,
/// lecture series, or podcast show — whose chapters were collapsed under their
/// shared `parentIdentifier` (`playsWholeWork == true`).
struct RecentWork: Identifiable {
    /// Stable work key: `work:<parentIdentifier>` for collapsed works, or the
    /// track id for standalone music.
    let id: String
    /// The most-recently-played representative track for this work.
    let track: Track
    /// Authoritative media kind for this work (persisted at play time, with a
    /// fallback to `Track.inferredMediaKind` for legacy history rows).
    let mediaKind: MediaKind
    /// When true, tapping resumes the whole work from its saved position rather
    /// than playing just the representative track.
    let playsWholeWork: Bool

    /// The parent identifier for a whole work, or nil for a standalone track.
    var workIdentifier: String? { playsWholeWork ? track.parentIdentifier : nil }

    /// Title shown on the card: the collection/book title when known, otherwise
    /// the representative track's title.
    var displayTitle: String {
        if playsWholeWork {
            if let coll = track.collectionTitle, !coll.isEmpty { return coll }
        }
        return track.title
    }

    /// Subtitle shown on the card (author/creator).
    var displaySubtitle: String { track.artist }
}
