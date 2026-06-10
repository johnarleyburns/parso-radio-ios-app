import Foundation

@MainActor
final class OfflineDownloadService: ObservableObject {
    struct DownloadProgress {
        var total: Int
        var completed: Int
        var failed: Int
        var label: String
        var isCancelled: Bool = false
    }

    @Published var activeDownloads: [String: DownloadProgress] = [:]
    // Per-track download fraction (0...1) while a track is downloading; the
    // key is removed once the file is on disk. Powers the playlist row's
    // circular progress indicator.
    @Published var trackProgress: [String: Double] = [:]

    // Incremented after every single-track download/removal completes.
    // Views observe this to refresh stale Track.localFilePath values.
    @Published var singleTrackVersion = 0

    private let db: DatabaseService
    private let downloadManager: DownloadManager
    private var activeTasks: [String: Task<Void, Never>] = [:]

    // nonisolated: referenced from nonisolated default-argument expressions
    // (makeOffline limit:). A plain immutable Int is trivially concurrency-safe.
    nonisolated static let trackLimit = 100

    init(db: DatabaseService, downloadManager: DownloadManager) {
        self.db = db
        self.downloadManager = downloadManager
    }

    func makeOffline(channel: Channel, limit: Int = trackLimit) async {
        let jobId = channel.id
        guard activeTasks[jobId] == nil else { return }
        let tracks = await db.fetchTracks(forChannel: channel)
        let toDownload = Array(tracks
            .filter { $0.downloadURL != nil && $0.localFilePath == nil }
            .prefix(limit))
        await startDownloadJob(id: jobId, tracks: toDownload, label: channel.name)
    }

    func makeOffline(playlist: Playlist, limit: Int = trackLimit) async {
        let jobId = playlist.id
        guard activeTasks[jobId] == nil else { return }
        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        let toDownload = Array(tracks
            .filter { $0.downloadURL != nil && $0.localFilePath == nil }
            .prefix(limit))
        await startDownloadJob(id: jobId, tracks: toDownload, label: playlist.name)
    }

    /// Download a single track for offline playback. The progress dictionary
    /// is keyed by the track id so views can show a per-row spinner. Idempotent
    /// when the track is already on disk.
    func makeOffline(track: Track) async {
        let id = track.id
        guard activeTasks[id] == nil else { return }
        guard track.localFilePath == nil else { return }
        guard track.downloadURL != nil else { return }
        await startDownloadJob(id: id, tracks: [track], label: track.title, isSingleTrack: true)
    }

    /// Remove the downloaded file for a single track and clear its DB pointer.
    func removeOffline(track: Track) async {
        if let path = track.localFilePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        await db.markDownloaded(trackID: track.id, localPath: "")
        singleTrackVersion &+= 1
    }

    func removeOffline(channel: Channel) async {
        cancel(jobId: channel.id)
        let tracks = await db.fetchTracks(forChannel: channel)
        for track in tracks where track.localFilePath != nil {
            if let path = track.localFilePath {
                try? FileManager.default.removeItem(atPath: path)
            }
            await db.markDownloaded(trackID: track.id, localPath: "")
        }
    }

    func removeOffline(playlist: Playlist) async {
        cancel(jobId: playlist.id)
        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        for track in tracks where track.localFilePath != nil {
            if let path = track.localFilePath {
                try? FileManager.default.removeItem(atPath: path)
            }
            await db.markDownloaded(trackID: track.id, localPath: "")
        }
    }

    func cancel(jobId: String) {
        activeTasks[jobId]?.cancel()
        activeTasks[jobId] = nil
        activeDownloads[jobId] = nil
    }

    /// Cancel all in-flight downloads and delete every downloaded/imported audio
    /// file on disk. Used by Settings → "Clear All Data".
    func deleteAllDownloads() async {
        for (id, _) in activeTasks { cancel(jobId: id) }
        activeTasks.removeAll(); activeDownloads.removeAll(); trackProgress.removeAll()
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    // Storage summary: total bytes used in the audio directory
    var offlineStorageSummary: String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio")
        var bytes: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let fileURL as URL in enumerator {
                bytes += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    // MARK: - Private

    private func startDownloadJob(id: String, tracks: [Track], label: String, isSingleTrack: Bool = false) async {
        activeDownloads[id] = DownloadProgress(
            total: tracks.count,
            completed: 0,
            failed: 0,
            label: label
        )
        let task = Task { [weak self] in
            for track in tracks {
                guard !Task.isCancelled else { break }
                let trackId = track.id
                await MainActor.run { self?.trackProgress[trackId] = 0 }
                await self?.downloadManager.download(track: track) { fraction in
                    Task { @MainActor in self?.trackProgress[trackId] = fraction }
                }
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.trackProgress[trackId] = nil          // done → row reads localFilePath
                    self?.activeDownloads[id]?.completed += 1
                }
            }
            await MainActor.run {
                self?.activeDownloads[id] = nil
                self?.activeTasks[id] = nil
                if isSingleTrack { self?.singleTrackVersion &+= 1 }
            }
        }
        activeTasks[id] = task
    }
}
