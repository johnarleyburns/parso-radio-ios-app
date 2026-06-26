import Foundation

@MainActor
final class WholeItemController {
    private let db: DatabaseService
    private let archiveService: InternetArchiveService
    private let oxfordService: OxfordLecturesService
    private let queueManager: QueueManager
    private weak var playerVM: PlayerViewModel?

    init(db: DatabaseService, archiveService: InternetArchiveService,
         oxfordService: OxfordLecturesService = OxfordLecturesService(),
         queueManager: QueueManager, playerVM: PlayerViewModel) {
        self.db = db
        self.archiveService = archiveService
        self.oxfordService = oxfordService
        self.queueManager = queueManager
        self.playerVM = playerVM
    }

    func resolveItemParts(identifier: String) async -> [Track]? {
        guard let vm = playerVM else { return nil }
        if let cached = vm.itemPartsCache[identifier] {
            Log.playback.debug("[wholeItem] cache hit for \(identifier): \(cached?.count ?? 0) parts")
            return cached
        }

        let dbPartsRaw = await db.fetchTracks(forParentIdentifier: identifier)
        let dbParts = PlayerViewModel.dedupeParts(dbPartsRaw)
        Log.playback.debug("[wholeItem] DB parts for \(identifier): \(dbPartsRaw.count) (deduped \(dbParts.count))")
        if dbParts.count >= 2, PlayerViewModel.partsAreClean(dbParts) {
            let ordered = dbParts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
            // Self-heal: rewrite stored rows when duplicate bitrate variants were
            // collapsed so the triple bug never recurs for this item.
            if dbParts.count != dbPartsRaw.count {
                await db.deleteTracks(forParentIdentifier: identifier)
                await db.saveTracks(ordered)
            }
            vm.itemPartsCache[identifier] = ordered
            return ordered
        }

        if let itemTrack = await db.fetchTrack(id: identifier),
           itemTrack.isMultiPart == false {
            Log.playback.debug("[wholeItem] DB \(identifier) isMultiPart=false, caching nil")
            vm.itemPartsCache.updateValue(nil, forKey: identifier)
            return nil
        }

        if let itemTrack = await db.fetchTrack(id: identifier),
           itemTrack.source == "oxford_lectures" {
            Log.playback.debug("[wholeItem] Oxford fallback for \(identifier)")
            do {
                let unitSlug = itemTrack.rawCreator
                let fetched = try await oxfordService.fetchTracks(unitSlug: unitSlug.isEmpty ? identifier : unitSlug)
                let matching = fetched.filter { $0.parentIdentifier == identifier }
                if matching.count >= 2, PlayerViewModel.partsAreClean(matching) {
                    await db.saveTracks(matching)
                    await db.setIsMultiPart(true, forTrackId: identifier)
                    let ordered = matching.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
                    vm.itemPartsCache[identifier] = ordered
                    return ordered
                }
            } catch {
                Log.playback.error("[wholeItem] Oxford fallback failed: \(error)")
            }
        }

        Log.playback.debug("[wholeItem] Network fetch for \(identifier)")
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
                Log.playback.debug("[wholeItem] Network got \(fetched.count) parts, caching nil")
                await db.setIsMultiPart(false, forTrackId: identifier)
                vm.itemPartsCache.updateValue(nil, forKey: identifier)
                return nil
            }
            await db.deleteTracks(forParentIdentifier: identifier)
            await db.saveTracks(fetched)
            await db.setIsMultiPart(true, forTrackId: identifier)
            let ordered = fetched.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
            vm.itemPartsCache[identifier] = ordered
            return ordered
        } catch {
            Log.playback.error("[wholeItem] Network fallback failed: \(error)")
            vm.itemPartsCache.updateValue(nil, forKey: identifier)
            return nil
        }
    }

    func addEntireItemToPlaylist(_ playlist: Playlist) async {
        guard let vm = playerVM, let track = vm.currentTrack else { return }
        let identifier = track.parentIdentifier ?? track.id
        guard let parts = await resolveItemParts(identifier: identifier) else { return }
        await db.addTracksOrdered(parts, toPlaylist: playlist.id)
    }

    func playAlbumTracks(_ ordered: [Track], title: String,
                         mediaKind: MediaKind? = nil, origin: PlaybackContext.Origin = .directItem,
                         startSeek: Double? = nil) async {
        guard let vm = playerVM, !ordered.isEmpty else { return }
        vm.sessionRestore.saveAutosaveForCurrentTrack()
        // Stable album id derived from the shared parent identifier so the
        // playlist position key (`playlist:album:<parentIdentifier>`) survives
        // across sessions and entry points (search, Books-for-You, Jump back in)
        // and the whole work is resumable. Falls back to a random id only for
        // ad-hoc track lists with no parent.
        let albumId = ordered.first?.parentIdentifier.map { "album:\($0)" }
            ?? "album:\(UUID().uuidString)"
        let albumPlaylist = Playlist(
            id: albumId,
            name: title,
            createdAt: Date(),
            updatedAt: Date(),
            isFavorites: false,
            isKidSafe: false
        )
        let kind = mediaKind ?? ordered[0].mediaKind(in: nil)
        vm.currentChannel = nil
        vm.currentPlaybackContext = PlaybackContext(
            origin: origin, mediaKind: kind,
            title: title)
        vm.currentPlaylist = albumPlaylist
        vm.playlistTracks = ordered
        vm.playlistIndex = 0
        vm.playbackContextToken &+= 1
        vm.playHistory = []
        vm.channelDescription = title
        vm.shuffleMode = false
        vm.resetShuffledPlaylistState()
        vm.beginTransition(pre: ordered[0])
        await vm.playTrack(ordered[0], seekTo: startSeek, recordHistory: false)
    }

    func skipToNextBook() async {
        guard let vm = playerVM, let channel = vm.currentChannel,
              let current = vm.currentTrack else { return }
        if let first = await queueManager.firstPartOfNextBook(after: current, channel: channel) {
            await vm.playTrack(first, seekTo: 0, recordHistory: true)
        }
    }

    func skipToPreviousBook() async {
        guard let vm = playerVM, let channel = vm.currentChannel,
              let current = vm.currentTrack else { return }
        if let first = await queueManager.firstPartOfPreviousBook(before: current, channel: channel) {
            await vm.playTrack(first, seekTo: 0, recordHistory: true)
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
            vm.shuffleMode = false
        } else {
            ordered = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        }
        vm.sessionRestore.saveAutosaveForCurrentTrack()
        let albumPlaylist = Playlist(
            id: "album:\(identifier)",
            name: vm.itemDisplayName(for: track),
            createdAt: Date(),
            updatedAt: Date(),
            isFavorites: false,
            isKidSafe: false
        )
        let kind = vm.activeMediaKind
        vm.currentChannel = nil
        vm.currentPlaybackContext = PlaybackContext(
            origin: .directItem, mediaKind: kind,
            title: vm.itemDisplayName(for: track))
        vm.currentPlaylist = albumPlaylist
        vm.playlistTracks = ordered
        vm.playlistIndex = 0
        vm.playbackContextToken &+= 1
        vm.playHistory = []
        vm.shuffleMode = false
        vm.resetShuffledPlaylistState()
        vm.beginTransition(pre: ordered[0])
        await vm.playTrack(ordered[0], seekTo: nil, recordHistory: false)
    }
}
