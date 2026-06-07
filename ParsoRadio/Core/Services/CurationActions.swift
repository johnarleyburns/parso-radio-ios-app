import Foundation

@MainActor
final class CurationActions {
    let db: DatabaseService

    init(db: DatabaseService) { self.db = db }

    func addAllPartsToReview(track: Track, channelId: String) async {
        let parentId = track.parentIdentifier ?? track.id
        let parts = await db.fetchTracks(forParentIdentifier: parentId)
        guard !parts.isEmpty else { return }
        await db.saveTracks(parts)
        await db.ensureReviewSet(channelId: channelId, trackIds: parts.map(\.id))
    }
}
