import Foundation

/// On-disk cache for ONE remote audio file, filled by its contiguous prefix as
/// the file streams. Sequential playback (the common case) grows the prefix
/// naturally; when it reaches the content length the file is complete and can
/// double as the offline copy. Seeks past the prefix are served from the network
/// by the resource loader (this cache simply reports they aren't available yet).
///
/// All the fiddly offset/overlap bookkeeping lives here, deliberately isolated
/// from AVFoundation, so it is fully unit-testable (see ContiguousFileCacheTests).
/// The AVAssetResourceLoaderDelegate that drives it is a thin shell on top.
final class ContiguousFileCache {
    let fileURL: URL
    private let handle: FileHandle
    /// Contiguous bytes available from offset 0.
    private(set) var cachedLength: Int64
    /// Total size of the remote resource, once known (from the content-info probe).
    private(set) var contentLength: Int64?

    init?(fileURL: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            _ = fm.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let h = try? FileHandle(forUpdating: fileURL) else { return nil }
        self.fileURL = fileURL
        self.handle = h
        // Resume from whatever prefix is already on disk.
        self.cachedLength = (try? Int64(h.seekToEnd())) ?? 0
    }

    func setContentLength(_ n: Int64) {
        if contentLength == nil, n > 0 { contentLength = n }
    }

    /// True once the whole resource is cached contiguously.
    var isComplete: Bool {
        guard let c = contentLength, c > 0 else { return false }
        return cachedLength >= c
    }

    /// Append `data` (which begins at byte `offset` of the resource) to the
    /// contiguous prefix. Only the portion extending past `cachedLength` is
    /// written; chunks that start beyond the current end (a gap) are ignored so
    /// the prefix stays truly contiguous. Returns the count of NEW bytes added.
    @discardableResult
    func appendContiguous(_ data: Data, at offset: Int64) -> Int {
        let end = offset + Int64(data.count)
        // Must overlap or abut the current end, and must extend it.
        guard offset <= cachedLength, end > cachedLength else { return 0 }
        let skip = Int(cachedLength - offset)           // bytes we already have
        let fresh = data.subdata(in: skip ..< data.count)
        guard !fresh.isEmpty else { return 0 }
        do {
            try handle.seek(toOffset: UInt64(cachedLength))
            try handle.write(contentsOf: fresh)
            cachedLength += Int64(fresh.count)
            return fresh.count
        } catch {
            return 0
        }
    }

    /// Cached bytes for `[offset, offset+length)` if the WHOLE range is within the
    /// contiguous prefix, else nil (the loader must fetch it from the network).
    func read(offset: Int64, length: Int) -> Data? {
        guard offset >= 0, length > 0, offset + Int64(length) <= cachedLength else { return nil }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: length)
        } catch {
            return nil
        }
    }

    func close() { try? handle.close() }
}
