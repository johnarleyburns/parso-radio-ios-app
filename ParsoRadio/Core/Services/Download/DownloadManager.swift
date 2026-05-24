import Foundation

final class DownloadManager {
    private let db: DatabaseService
    private let fileStorage = FileStorageService()
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 3600  // allow up to 1 h for large audio files
        return URLSession(configuration: cfg)
    }()

    init(db: DatabaseService) {
        self.db = db
    }

    func download(track: Track, onProgress: (@Sendable (Double) -> Void)? = nil) async {
        // A whole-item IA track's downloadURL points at the item DIRECTORY, not a
        // playable file — downloading it just saves the directory listing as a
        // fake .mp3 that never plays (and which local-first would then serve).
        // Skip those; they stream via resolveAudioURL instead. Per-file IA ids
        // (contain "/"), FMA and imported tracks have real file URLs.
        if track.source == "internet_archive", !track.id.contains("/") { return }
        let dest = fileStorage.localURL(for: track.id)
        if FileManager.default.fileExists(atPath: dest.path) {
            await db.markDownloaded(trackID: track.id, localPath: dest.path)
            onProgress?(1.0)
            return
        }

        guard let url = track.downloadURL else { return }

        do {
            let tmpURL: URL
            if let onProgress {
                let delegate = DownloadProgressDelegate(onProgress: onProgress)
                (tmpURL, _) = try await session.download(from: url, delegate: delegate)
            } else {
                (tmpURL, _) = try await session.download(from: url)
            }
            let dir = dest.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: tmpURL, to: dest)
            await db.markDownloaded(trackID: track.id, localPath: dest.path)
            onProgress?(1.0)
        } catch {
            // Download failed — track remains stream-only
        }
    }

    func prefetchNext(_ tracks: [Track]) {
        Task {
            for track in tracks.prefix(5) {
                let dest = fileStorage.localURL(for: track.id)
                guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
                await download(track: track)
            }
        }
    }
}

/// Reports byte-level progress for a single download. URLSession's
/// `download(from:delegate:)` async API delivers the file itself; this
/// delegate is only used for the incremental `didWriteData` callbacks.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    // Required by the protocol; the async download API handles file delivery,
    // so there's nothing to do here.
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
