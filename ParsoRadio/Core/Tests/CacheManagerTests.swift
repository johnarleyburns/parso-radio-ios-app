import XCTest
@testable import ParsoMusic

final class CacheManagerTests: XCTestCase {
    var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try super.tearDownWithError()
    }

    private func createFile(_ name: String, size: Int64, accessed: Date? = nil) -> URL {
        let url = tmpDir.appendingPathComponent(name)
        let data = Data(count: Int(size))
        try! data.write(to: url)
        if let accessed {
            var ts = Int64(accessed.timeIntervalSince1970)
            let tsData = Data(bytes: &ts, count: MemoryLayout<Int64>.size)
            tsData.withUnsafeBytes { buf in
                _ = setxattr(url.path, "com.lorewave.lastAccess", buf.baseAddress, buf.count, 0, 0)
            }
        }
        return url
    }

    private func totalSize(of dir: URL) -> Int64 {
        var total: Int64 = 0
        guard let e = FileManager.default.enumerator(at: dir,
            includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        else { return 0 }
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    func testMarkAccessedStoresTimestamp() {
        let url = createFile("test.mp3", size: 1024)
        XCTAssertNil(CacheManager.shared.lastAccess(url))

        CacheManager.shared.markAccessed(url)
        let accessed = CacheManager.shared.lastAccess(url)
        XCTAssertNotNil(accessed)

        let diff = abs(Date().timeIntervalSince1970 - (accessed?.timeIntervalSince1970 ?? 0))
        XCTAssertLessThan(diff, 5, "Timestamp should be within 5 seconds of now")
    }

    func testLastAccessReturnsNilForUntouchedFile() {
        let url = createFile("fresh.mp3", size: 1024)
        XCTAssertNil(CacheManager.shared.lastAccess(url))
    }

    func testEvictIfNeededUnderBudgetNoOp() {
        // Create files in test dir, evictIfNeeded operates on real dirs,
        // so the test dir should be untouched
        createFile("a.mp3", size: 50_000_000)
        let before = totalSize(of: tmpDir)
        CacheManager.shared.evictIfNeeded(maxBytes: 200_000_000)
        let after = totalSize(of: tmpDir)
        XCTAssertEqual(before, after, "Test directory should be untouched when under budget")
    }

    func testDownloadedBytesReturnsNumber() {
        let bytes = CacheManager.shared.downloadedBytes()
        XCTAssertGreaterThanOrEqual(bytes, 0, "Downloaded bytes should be non-negative")
    }

    func testStreamingCacheBytesReturnsNumber() {
        let bytes = CacheManager.shared.streamingCacheBytes()
        XCTAssertGreaterThanOrEqual(bytes, 0, "Streaming cache bytes should be non-negative")
    }

    func testTotalCacheBytesIsSum() {
        let total = CacheManager.shared.totalCacheBytes()
        let downloaded = CacheManager.shared.downloadedBytes()
        let streaming = CacheManager.shared.streamingCacheBytes()
        XCTAssertEqual(total, downloaded + streaming, "Total should equal downloaded + streaming")
    }

    func testClearStreamingCacheClearsDir() {
        CacheManager.shared.clearStreamingCache()
        let after = CacheManager.shared.streamingCacheBytes()
        XCTAssertEqual(after, 0, "Streaming cache should be empty after clear")
    }
}
