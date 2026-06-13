import Foundation

@MainActor
final class SessionRestoreController {
    private let db: DatabaseService
    private weak var playerVM: PlayerViewModel?

    init(db: DatabaseService, playerVM: PlayerViewModel) {
        self.db = db
        self.playerVM = playerVM
    }

    static let channelIdMigrations: [String: String] = [
        "classical-guitar": "guitar-classical",
        "spanish-guitar": "guitar-classical"
    ]

    static func migratedChannelId(_ id: String?) -> String? {
        guard let id else { return nil }
        return channelIdMigrations[id] ?? id
    }

    func persistSession(position: Double) {
        guard let vm = playerVM else { return }
        let d = UserDefaults.standard
        guard let track = vm.currentTrack,
              vm.currentChannel?.mediaKind != .ambient else { return }
        guard !vm.isAuditioning else { return }
        if let pl = vm.currentPlaylist {
            d.set("playlist", forKey: "session.kind")
            d.set(pl.id, forKey: "session.contextId")
        } else if let ch = vm.currentChannel {
            d.set("channel", forKey: "session.kind")
            d.set(ch.id, forKey: "session.contextId")
        } else {
            d.set("track", forKey: "session.kind")
            d.removeObject(forKey: "session.contextId")
        }
        d.set(track.id, forKey: "session.trackId")
        d.set(position, forKey: "session.position")
    }

    func restoreLastSession(fallbackChannel: Channel, autoPlay: Bool) async {
        guard let vm = playerVM else { return }
        let d = UserDefaults.standard
        let kind = d.string(forKey: "session.kind")
        let contextId = d.string(forKey: "session.contextId")
        let savedTrackId = d.string(forKey: "session.trackId")
        let savedPosition = d.double(forKey: "session.position")

        if kind == "playlist", let pid = contextId,
           let pl = await db.fetchPlaylists().first(where: { $0.id == pid }) {
            await vm.resumePlaylist(pl, autoPlay: autoPlay)
            if let cur = vm.currentTrack, cur.id == savedTrackId,
               savedPosition > vm.currentPosition + 2 {
                await vm.playTrack(cur, seekTo: savedPosition,
                                    recordHistory: false, autoPlay: autoPlay)
            }
            return
        }

        let channelId = Self.migratedChannelId(
            kind == "channel" ? contextId
                : (Self.migratedChannelId(d.string(forKey: "lastChannelId"))))
        let channel = Channel.defaults.first { $0.id == channelId } ?? fallbackChannel
        await vm.load(channel: channel, autoPlay: autoPlay)

        if let tid = savedTrackId, let t = await db.fetchTrack(id: tid),
           NetworkMonitor.shared.isOnline || t.localFilePath != nil {
            let isCurated = channel.category == "Curated" && channel.iaQueryEntry != nil
            let approved = isCurated
                ? Set(LiveCurationStore.shared.pool(for: channel.id).map(\.id))
                : nil
            if isCurated, let approved, !approved.isEmpty, !approved.contains(tid) {
            } else if vm.currentTrack?.id != tid {
                await vm.playTrack(t, seekTo: savedPosition > 1 ? savedPosition : nil,
                                    autoPlay: autoPlay)
            } else if savedPosition > vm.currentPosition + 2 {
                await vm.playTrack(t, seekTo: savedPosition,
                                    recordHistory: false, autoPlay: autoPlay)
            }
        }
    }
}
