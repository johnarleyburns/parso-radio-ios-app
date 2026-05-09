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

    func download(track: Track) async {
        let dest = fileStorage.localURL(for: track.id)
        if FileManager.default.fileExists(atPath: dest.path) {
            await db.markDownloaded(trackID: track.id, localPath: dest.path)
            return
        }

        guard let url = track.downloadURL else { return }

        do {
            let (tmpURL, _) = try await session.download(from: url)
            let dir = dest.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: tmpURL, to: dest)
            await db.markDownloaded(trackID: track.id, localPath: dest.path)
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
