import Foundation

struct CacheManager {
    static let shared = CacheManager()

    private let fileManager = FileManager.default
    private let xattrName = "com.lorewave.lastAccess"
    private let audioDir: URL
    private let streamingDir: URL

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        audioDir = docs.appendingPathComponent("audio")
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        streamingDir = caches.appendingPathComponent("StreamingCache")
    }

    // MARK: - Size queries

    func downloadedBytes() -> Int64 {
        sizeOfDirectory(audioDir)
    }

    func streamingCacheBytes() -> Int64 {
        sizeOfDirectory(streamingDir)
    }

    func totalCacheBytes() -> Int64 {
        downloadedBytes() + streamingCacheBytes()
    }

    // MARK: - Access tracking (xattr-based LRU)

    func markAccessed(_ url: URL) {
        var ts = Int64(Date().timeIntervalSince1970)
        let tsData = Data(bytes: &ts, count: MemoryLayout<Int64>.size)
        tsData.withUnsafeBytes { buf in
            _ = setxattr(url.path, xattrName, buf.baseAddress, buf.count, 0, 0)
        }
    }

    func lastAccess(_ url: URL) -> Date? {
        guard let data = getxattrData(url) else { return nil }
        var ts: Int64 = 0
        _ = data.withUnsafeBytes { buf in
            ts = buf.load(as: Int64.self)
        }
        return ts > 0 ? Date(timeIntervalSince1970: TimeInterval(ts)) : nil
    }

    // MARK: - Budget enforcement (LRU eviction)

    func evictIfNeeded(maxBytes: Int64) {
        let total = totalCacheBytes()
        guard total > maxBytes else { return }

        // Gather all cache files with access timestamps
        var files: [(url: URL, accessed: Date, size: Int64)] = []
        gatherFiles(in: audioDir, into: &files)
        gatherFiles(in: streamingDir, into: &files)

        // Sort oldest-first (LRU)
        files.sort { $0.accessed < $1.accessed }

        var removed: Int64 = 0
        for file in files {
            guard total - removed > maxBytes else { break }
            try? fileManager.removeItem(at: file.url)
            removed += file.size
        }
    }

    // MARK: - Clear caches

    func clearStreamingCache() async {
        await Task.detached(priority: .utility) { [streamingDir, fileManager] in
            try? fileManager.removeItem(at: streamingDir)
        }.value
    }

    func clearDownloads() async {
        await Task.detached(priority: .utility) { [audioDir, fileManager] in
            try? fileManager.removeItem(at: audioDir)
        }.value
    }

    // MARK: - Private helpers

    private func sizeOfDirectory(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    private func gatherFiles(in dir: URL, into files: inout [(url: URL, accessed: Date, size: Int64)]) {
        guard let enumerator = fileManager.enumerator(at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize else { continue }
            let accessed = lastAccess(fileURL) ?? Date.distantPast
            files.append((url: fileURL, accessed: accessed, size: Int64(size)))
        }
    }

    private func getxattrData(_ url: URL) -> Data? {
        let raw = url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let len = getxattr(path, xattrName, nil, 0, 0, 0)
            guard len > 0 else { return nil }
            var buf = Data(count: len)
            let result = buf.withUnsafeMutableBytes { ptr in
                getxattr(path, xattrName, ptr.baseAddress, len, 0, 0)
            }
            guard result > 0 else { return nil }
            return buf
        }
        return raw
    }
}
