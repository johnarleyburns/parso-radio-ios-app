import Foundation

@MainActor
final class WholeItemController {
    private let db: DatabaseService
    private let archiveService: InternetArchiveService
    private let queueManager: QueueManager
    private weak var playerVM: PlayerViewModel?

    init(db: DatabaseService, archiveService: InternetArchiveService,
         queueManager: QueueManager, playerVM: PlayerViewModel) {
        self.db = db
        self.archiveService = archiveService
        self.queueManager = queueManager
        self.playerVM = playerVM
    }

    func resolveItemParts(identifier: String) async -> [Track]? {
        guard let vm = playerVM else { return nil }
        if let cached = vm.itemPartsCache[identifier] { return cached }

        let dbParts = await db.fetchTracks(forParentIdentifier: identifier)
        if dbParts.count >= 2, PlayerViewModel.partsAreClean(dbParts) {
            let ordered = dbParts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
            vm.itemPartsCache[identifier] = ordered
            return ordered
        }

        if let itemTrack = await db.fetchTrack(id: identifier),
           itemTrack.isMultiPart == false {
            vm.itemPartsCache.updateValue(nil, forKey: identifier)
            return nil
        }

        do {
            let fetched = try await withThrowingTaskGroup(of: [Track].self) { group in
                group.addTask {
                    let shortSession = URLSession(configuration: {
                        let c = URLSessionConfiguration.default
                        c.timeoutIntervalForRequest = 8
                        c.timeoutIntervalForResource = 12
                        return c
                    }())
                    let svc = InternetArchiveService(session: shortSession)
                    return try await svc.fetchTracksForIdentifier(identifier)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    throw URLError(.timedOut)
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            if fetched.count <= 1 {
                await db.setIsMultiPart(false, forTrackId: identifier)
                vm.itemPartsCache.updateValue(nil, forKey: identifier)
                return nil
            }
            await db.deleteTracks(forParentIdentifier: identifier)
            await db.saveTracks(fetched)
            let ordered = fetched.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
            vm.itemPartsCache[identifier] = ordered
            return ordered
        } catch {
            vm.itemPartsCache.updateValue(nil, forKey: identifier)
            return nil
        }
    }

    func probeCurrentTrack() {
        guard let vm = playerVM else { return }
        guard let track = vm.currentTrack, track.source == "internet_archive" else {
            vm.currentTrackIsMultiPart = false
            vm.currentItemChapterCount = 0
            vm.currentItemTotalDuration = 0
            vm.currentItemPartIndex = nil
            return
        }
        let identifier = track.parentIdentifier ?? track.id
        Task { [weak self, weak vm] in
            guard let self, let vm else { return }
            let parts = await self.resolveItemParts(identifier: identifier)
            guard vm.currentTrack?.id == track.id ||
                  (track.parentIdentifier != nil &&
                   vm.currentTrack?.parentIdentifier == track.parentIdentifier)
            else { return }
            vm.currentTrackIsMultiPart = (parts != nil)
            guard let parts else {
                vm.currentItemChapterCount = 0
                vm.currentItemTotalDuration = 0
                vm.currentItemPartIndex = nil
                return
            }
            vm.currentItemChapterCount = parts.count
            vm.currentItemTotalDuration = parts.reduce(0.0) { $0 + max(0, $1.duration) }
            if let pn = vm.currentTrack?.partNumber {
                vm.currentItemPartIndex = pn
            } else if let cur = vm.currentTrack?.id,
                      let idx = parts.firstIndex(where: { $0.id == cur }) {
                vm.currentItemPartIndex = idx + 1
            } else {
                vm.currentItemPartIndex = 1
            }
        }
    }

    func addEntireItemToPlaylist(_ playlist: Playlist) async {
        guard let vm = playerVM, let track = vm.currentTrack else { return }
        let identifier = track.parentIdentifier ?? track.id
        guard let parts = await resolveItemParts(identifier: identifier) else { return }
        for part in parts {
            await vm.db.addTrack(part, toPlaylist: playlist.id)
        }
    }

    func playEntireCurrentItem() async {
        guard let vm = playerVM, let track = vm.currentTrack else { return }
        let identifier = track.parentIdentifier ?? track.id
        guard let parts = await resolveItemParts(identifier: identifier),
              !parts.isEmpty else { return }
        let ordered: [Track]
        if vm.shuffleMode, parts.count > 1 {
            ordered = parts.shuffled()
        } else {
            ordered = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        }
        vm.saveAutosaveForCurrentTrack()
        let albumPlaylist = Playlist(
            id: "album:\(identifier)",
            name: vm.itemDisplayName(for: track),
            createdAt: Date(),
            updatedAt: Date(),
            isFavorites: false,
            isKidSafe: false
        )
        vm.currentChannel = nil
        vm.currentPlaylist = albumPlaylist
        vm.playlistTracks = ordered
        vm.playlistIndex = 0
        vm.playbackContextToken &+= 1
        vm.playHistory = []
        await vm.playTrack(ordered[0], seekTo: nil, recordHistory: false)
    }

    func playAlbumTracks(_ ordered: [Track], title: String) async {
        await playerVM?.playAlbumTracks(ordered, title: title)
    }
}
