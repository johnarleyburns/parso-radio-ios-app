import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let audioPlayer: AudioPlayerService

    private let db: DatabaseService
    private let archiveService: InternetArchiveService
    private let fmaService: FMAService
    private let queueManager: QueueManager
    private let downloadManager: DownloadManager
    private(set) var currentChannel: Channel?

    init(
        db: DatabaseService,
        archiveService: InternetArchiveService,
        fmaService: FMAService,
        queueManager: QueueManager,
        audioPlayer: AudioPlayerService,
        downloadManager: DownloadManager
    ) {
        self.db = db
        self.archiveService = archiveService
        self.fmaService = fmaService
        self.queueManager = queueManager
        self.audioPlayer = audioPlayer
        self.downloadManager = downloadManager

        audioPlayer.onTrackFinished = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.advanceToNext()
            }
        }
    }

    func load(channel: Channel) async {
        currentChannel = channel
        isLoading = true
        errorMessage = nil

        do {
            let fetched: [Track]
            let iaSvc = archiveService
            let fmaSvc = fmaService

            if channel.composers.isEmpty {
                // Tag channels: IA + FMA in parallel; FMA errors are non-fatal.
                async let iaTracks = iaSvc.fetchTracks(tags: channel.tags)
                let fmaTracks = (try? await fmaSvc.fetchTracks(forChannel: channel)) ?? []
                let iaResults = try await iaTracks
                var seen = Set<String>()
                fetched = (iaResults + fmaTracks).filter { seen.insert($0.id).inserted }
            } else {
                // Composer channels: IA + Musopen(IA) + FMA all in parallel.
                // Musopen and FMA errors are non-fatal.
                async let iaTracks = iaSvc.fetchTracks(
                    composers: channel.composers,
                    instruments: channel.instruments
                )
                var supplemental: [Track] = []
                await withTaskGroup(of: [Track].self) { group in
                    for composer in channel.composers {
                        group.addTask { (try? await iaSvc.fetchMusopenTracks(composer: composer)) ?? [] }
                    }
                    group.addTask { (try? await fmaSvc.fetchTracks(forChannel: channel)) ?? [] }
                    for await tracks in group { supplemental.append(contentsOf: tracks) }
                }
                let iaResults = try await iaTracks
                var seen = Set<String>()
                fetched = (iaResults + supplemental).filter { seen.insert($0.id).inserted }
            }
            await db.saveTracks(fetched)
            downloadManager.prefetchNext(fetched)
        } catch {
            // Non-fatal: play from whatever is already in the DB
            if currentTrack == nil {
                errorMessage = "Could not refresh tracks."
            }
        }

        await advanceToNext()
        isLoading = false
    }

    func togglePlayPause() {
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            isPlaying = false
        } else if currentTrack != nil {
            audioPlayer.resume()
            isPlaying = true
        }
    }

    func skip() {
        audioPlayer.skip()
        isPlaying = false
        Task { await advanceToNext() }
    }

    // MARK: - Private

    private func advanceToNext() async {
        guard let channel = currentChannel else { return }
        guard let track = await queueManager.nextTrack(channel: channel) else {
            currentTrack = nil
            isPlaying = false
            if errorMessage == nil {
                errorMessage = "No tracks available for this channel."
            }
            isLoading = false
            return
        }
        await playTrack(track)
    }

    private func playTrack(_ track: Track) async {
        currentTrack = track
        isLoading = true
        defer { isLoading = false }

        do {
            let url: URL
            if let localPath = track.localFilePath,
               FileManager.default.fileExists(atPath: localPath) {
                url = URL(fileURLWithPath: localPath)
            } else if track.source == "internet_archive" {
                url = try await archiveService.resolveAudioURL(for: track.id)
            } else {
                // FMA and other sources store a directly playable stream URL.
                url = track.streamURL
            }
            audioPlayer.play(url: url, track: track)
            isPlaying = true
            errorMessage = nil
        } catch {
            errorMessage = "Could not load \"\(track.title)\"."
            isPlaying = false
        }
    }
}
