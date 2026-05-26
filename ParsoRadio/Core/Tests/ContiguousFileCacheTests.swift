import XCTest
@testable import ParsoMusic

final class ContiguousFileCacheTests: XCTestCase {

    private func tempCache() -> ContiguousFileCache {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parso-cache-test")
            .appendingPathComponent(UUID().uuidString + ".bin")
        return ContiguousFileCache(fileURL: url)!
    }

    private func bytes(_ n: Int, fill: UInt8 = 0xAB) -> Data { Data(repeating: fill, count: n) }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("parso-cache-test"))
    }

    func testSequentialAppendGrowsPrefix() {
        let c = tempCache(); defer { c.close() }
        XCTAssertEqual(c.appendContiguous(bytes(100), at: 0), 100)
        XCTAssertEqual(c.cachedLength, 100)
        XCTAssertEqual(c.appendContiguous(bytes(50), at: 100), 50)
        XCTAssertEqual(c.cachedLength, 150)
    }

    func testReadServesOnlyFullyCachedRanges() {
        let c = tempCache(); defer { c.close() }
        c.appendContiguous(bytes(100, fill: 0x11), at: 0)
        XCTAssertEqual(c.read(offset: 0, length: 50)?.count, 50)
        XCTAssertEqual(c.read(offset: 50, length: 50)?.count, 50)
        XCTAssertNil(c.read(offset: 80, length: 40), "range extending past the prefix is not served")
        XCTAssertNil(c.read(offset: 200, length: 10), "range beyond the prefix is not served")
    }

    func testGapChunkIsIgnored() {
        let c = tempCache(); defer { c.close() }
        c.appendContiguous(bytes(100), at: 0)
        XCTAssertEqual(c.appendContiguous(bytes(50), at: 200), 0, "a non-contiguous chunk is dropped")
        XCTAssertEqual(c.cachedLength, 100, "prefix unchanged by a gap chunk")
    }

    func testOverlappingChunkAddsOnlyNewBytes() {
        let c = tempCache(); defer { c.close() }
        c.appendContiguous(bytes(100), at: 0)
        // A chunk [50,150) overlaps the prefix; only [100,150) is new.
        XCTAssertEqual(c.appendContiguous(bytes(100), at: 50), 50)
        XCTAssertEqual(c.cachedLength, 150)
    }

    func testCompletenessTracksContentLength() {
        let c = tempCache(); defer { c.close() }
        c.setContentLength(150)
        XCTAssertFalse(c.isComplete)
        c.appendContiguous(bytes(150), at: 0)
        XCTAssertTrue(c.isComplete, "prefix reached the content length")
    }

    func testReopenResumesFromExistingPrefix() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parso-cache-test")
            .appendingPathComponent(UUID().uuidString + ".bin")
        let c1 = ContiguousFileCache(fileURL: url)!
        c1.appendContiguous(bytes(100), at: 0)
        c1.close()
        let c2 = ContiguousFileCache(fileURL: url)!; defer { c2.close() }
        XCTAssertEqual(c2.cachedLength, 100, "a reopened cache resumes from the bytes on disk")
        XCTAssertEqual(c2.read(offset: 0, length: 100)?.count, 100)
    }
}
