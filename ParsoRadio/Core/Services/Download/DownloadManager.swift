import Foundation

final class DownloadManager: NSObject {
    private let db: DatabaseService
    private let fileStorage = FileStorageService()
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private let lock = NSLock()

    @Published var progress: [String: Double] = [:]

    init(db: DatabaseService) {
        self.db = db
    }

    func download(track: Track) async {
        let dest = fileStorage.localURL(for: track.id)
        if FileManager.default.fileExists(atPath: dest.path) {
            db.markDownloaded(trackID: track.id, localPath: dest.path)
            return
        }

        guard let url = track.downloadURL else { return }

        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: url)
            let dir = dest.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: tmpURL, to: dest)
            db.markDownloaded(trackID: track.id, localPath: dest.path)
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
