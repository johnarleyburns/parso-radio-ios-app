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

    func playRecentTrack(_ track: Track) async {
        playerVM?.currentChannel = nil
        await playerVM?.playTrack(track, seekTo: nil)
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
