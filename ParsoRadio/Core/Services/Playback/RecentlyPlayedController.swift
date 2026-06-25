import Foundation

@MainActor
final class RecentlyPlayedController {
    private let db: DatabaseService
    private weak var playerVM: PlayerViewModel?

    init(db: DatabaseService, playerVM: PlayerViewModel) {
        self.db = db
        self.playerVM = playerVM
    }

    func recentlyPlayedTracks(limit: Int = 30) async -> [Track] {
        await db.fetchRecentlyPlayedTracks(limit: limit)
    }

    func recentlyPlayedWorks(limit: Int = 30) async -> [RecentWork] {
        await db.fetchRecentlyPlayedWorks(limit: limit)
    }

    func playRecentTrack(_ track: Track) async {
        guard let vm = playerVM else { return }
        vm.currentChannel = nil
        vm.currentPlaybackContext = PlaybackContext(
            origin: .recentlyPlayed, mediaKind: track.inferredMediaKind,
            title: track.title)
        await vm.playTrack(track, seekTo: nil)
    }

    /// Resume a whole spoken work (book/lecture/podcast) from its most recent
    /// saved position. The work's persisted media kind drives the now-playing
    /// surface so a chapter never renders as a music track. Music entries fall
    /// back to playing the single representative track.
    func resumeWork(_ work: RecentWork) async {
        guard let vm = playerVM else { return }
        guard work.playsWholeWork, let parentId = work.workIdentifier else {
            vm.currentChannel = nil
            vm.currentPlaybackContext = PlaybackContext(
                origin: .recentlyPlayed, mediaKind: work.mediaKind, title: work.track.title)
            await vm.playTrack(work.track, seekTo: nil)
            return
        }

        guard let parts = await vm.resolveItemParts(identifier: parentId), !parts.isEmpty else {
            vm.currentChannel = nil
            vm.currentPlaybackContext = PlaybackContext(
                origin: .recentlyPlayed, mediaKind: work.mediaKind, title: work.displayTitle)
            await vm.playTrack(work.track, seekTo: nil)
            return
        }

        let ordered = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        let saved = await db.loadPosition(
            channelId: PlayerViewModel.bookPositionKey(parentIdentifier: parentId))

        var startList = ordered
        var seek: Double? = nil
        if let saved, let idx = ordered.firstIndex(where: { $0.id == saved.trackId }) {
            startList = Array(ordered[idx...]) + Array(ordered[..<idx])
            seek = saved.seconds
        }

        await vm.playAlbumTracks(startList, title: work.displayTitle,
                                 mediaKind: work.mediaKind, origin: .recentlyPlayed,
                                 startSeek: seek)
    }

    func removeFromRecentlyPlayed(_ track: Track) async {
        await db.deletePlayHistory(trackId: track.id)
    }

    func clearRecentlyPlayed() async {
        await db.clearAllPlayHistory()
    }

    func clearListeningHistory() async {
        await db.clearAllPlayHistory()
    }
}
