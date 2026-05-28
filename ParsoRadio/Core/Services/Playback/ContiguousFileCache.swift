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
    // AVAssetResourceLoader issues loading requests concurrently (e.g. a
    // content-info request and a seek's data request at the same time), and the
    // delegate fans each out to its own Task. They all share this one cache, so
    // every FileHandle seek+read / seek+write pair AND the length fields must be
    // serialised — otherwise two Tasks interleave their seeks and reads return
    // bytes from the wrong offset (garbage to AVPlayer → "plays no sound").
    // This was the back-button-on-a-seek hang with the streaming cache on.
    private let lock = NSLock()
    private var _cachedLength: Int64
    private var _contentLength: Int64?

    /// Contiguous bytes available from offset 0.
    var cachedLength: Int64 { lock.lock(); defer { lock.unlock() }; return _cachedLength }
    /// Total size of the remote resource, once known (from the content-info probe).
    var contentLength: Int64? { lock.lock(); defer { lock.unlock() }; return _contentLength }

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
        self._cachedLength = (try? Int64(h.seekToEnd())) ?? 0
    }

    func setContentLength(_ n: Int64) {
        lock.lock(); defer { lock.unlock() }
        if _contentLength == nil, n > 0 { _contentLength = n }
    }

    /// True once the whole resource is cached contiguously.
    var isComplete: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let c = _contentLength, c > 0 else { return false }
        return _cachedLength >= c
    }

    /// Append `data` (which begins at byte `offset` of the resource) to the
    /// contiguous prefix. Only the portion extending past `cachedLength` is
    /// written; chunks that start beyond the current end (a gap) are ignored so
    /// the prefix stays truly contiguous. Returns the count of NEW bytes added.
    @discardableResult
    func appendContiguous(_ data: Data, at offset: Int64) -> Int {
        lock.lock(); defer { lock.unlock() }
        let end = offset + Int64(data.count)
        // Must overlap or abut the current end, and must extend it.
        guard offset <= _cachedLength, end > _cachedLength else { return 0 }
        let skip = Int(_cachedLength - offset)          // bytes we already have
        let fresh = data.subdata(in: skip ..< data.count)
        guard !fresh.isEmpty else { return 0 }
        do {
            try handle.seek(toOffset: UInt64(_cachedLength))
            try handle.write(contentsOf: fresh)
            _cachedLength += Int64(fresh.count)
            return fresh.count
        } catch {
            return 0
        }
    }

    /// Cached bytes for `[offset, offset+length)` if the WHOLE range is within the
    /// contiguous prefix, else nil (the loader must fetch it from the network).
    func read(offset: Int64, length: Int) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard offset >= 0, length > 0, offset + Int64(length) <= _cachedLength else { return nil }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: length)
        } catch {
            return nil
        }
    }

    func close() { lock.lock(); defer { lock.unlock() }; try? handle.close() }
}
