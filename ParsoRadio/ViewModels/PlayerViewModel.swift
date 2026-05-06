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
    private let queueManager: QueueManager
    private let downloadManager: DownloadManager
    private(set) var currentChannel: Channel?

    init(
        db: DatabaseService,
        archiveService: InternetArchiveService,
        queueManager: QueueManager,
        audioPlayer: AudioPlayerService,
        downloadManager: DownloadManager
    ) {
        self.db = db
        self.archiveService = archiveService
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
            if channel.composers.isEmpty {
                fetched = try await archiveService.fetchTracks(tags: channel.tags)
            } else {
                fetched = try await archiveService.fetchTracks(
                    composers: channel.composers,
                    instruments: channel.instruments
                )
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
            } else {
                url = try await archiveService.resolveAudioURL(for: track.id)
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
