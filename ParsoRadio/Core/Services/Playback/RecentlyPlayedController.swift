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
        vm.beginDirectPlaybackContext(
            pre: track,
            context: PlaybackContext(
                origin: .recentlyPlayed, mediaKind: track.inferredMediaKind,
                title: track.title),
            description: track.title)
        await vm.playTrack(track, seekTo: nil, recordHistory: false)
    }

    /// Resume a whole work from "Jump back in". A spoken work (book/lecture/
    /// podcast) resumes the saved chapter from its saved offset. A music album
    /// resumes the EXACT track the user last played from that album (the
    /// representative track), at its saved position — or that track's start if
    /// it was already finished or has no saved position — then continues through
    /// the rest of the album. The persisted media kind drives the now-playing
    /// surface so a chapter never renders as a music track.
    func resumeWork(_ work: RecentWork) async {
        guard let vm = playerVM else { return }
        guard work.playsWholeWork, let parentId = work.workIdentifier else {
            vm.beginDirectPlaybackContext(
                pre: work.track,
                context: PlaybackContext(
                    origin: .recentlyPlayed, mediaKind: work.mediaKind,
                    title: work.track.title),
                description: work.displayTitle)
            await vm.playTrack(work.track, seekTo: nil, recordHistory: false)
            return
        }

        guard let parts = await vm.resolveItemParts(identifier: parentId), !parts.isEmpty else {
            vm.beginDirectPlaybackContext(
                pre: work.track,
                context: PlaybackContext(
                    origin: .recentlyPlayed, mediaKind: work.mediaKind,
                    title: work.displayTitle),
                description: work.displayTitle)
            await vm.playTrack(work.track, seekTo: nil, recordHistory: false)
            return
        }

        let ordered = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }

        if work.mediaKind == .music {
            await resumeMusicAlbum(work, parentId: parentId, ordered: ordered)
            return
        }

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

    /// Music albums resume the exact track the user was on (the most-recently-
    /// played representative track), restarting it from the top if it was
    /// already finished or has no saved position, then continue the album.
    private func resumeMusicAlbum(_ work: RecentWork, parentId: String,
                                  ordered: [Track]) async {
        guard let vm = playerVM else { return }
        let repId = work.track.id

        var startList = ordered
        if let idx = ordered.firstIndex(where: { $0.id == repId }) {
            startList = Array(ordered[idx...]) + Array(ordered[..<idx])
        }

        // The track position we were at: prefer the album-context position,
        // then the per-track autosave for single-track plays.
        var savedSeconds: Double? = nil
        let saved = await db.loadPosition(
            channelId: PlayerViewModel.bookPositionKey(parentIdentifier: parentId))
        if let saved, saved.trackId == repId {
            savedSeconds = saved.seconds
        } else if let auto = await vm.autosavePosition(forTrack: repId) {
            savedSeconds = auto
        }

        // Start of the track if it was already finished (near the end) or we
        // have no usable position; otherwise resume at the saved offset.
        var seek: Double? = nil
        if let s = savedSeconds, s > 0 {
            let dur = startList.first?.duration ?? 0
            seek = (dur > 0 && s >= dur - 5) ? nil : s
        }

        await vm.playAlbumTracks(startList, title: work.displayTitle,
                                 mediaKind: .music, origin: .recentlyPlayed,
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
