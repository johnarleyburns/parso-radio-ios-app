import XCTest
@testable import ParsoMusic

// The delegate itself can only be validated on a real device (AVAssetResourceLoader
// drives it through AVPlayer). What IS testable: the URL scheme swap, the
// Content-Range parsing, and the MIME→UTI mapping — exercised here so they
// don't quietly regress.
final class CachingResourceLoaderDelegateTests: XCTestCase {

    func testCachingURLSwapsHTTPSScheme() {
        let url = URL(string: "https://archive.org/download/foo/bar.mp3")!
        let caching = CachingResourceLoaderDelegate.cachingURL(for: url)!
        XCTAssertEqual(caching.scheme, "parsocache")
        let back = CachingResourceLoaderDelegate.originalURL(from: caching)!
        XCTAssertEqual(back.absoluteString, url.absoluteString,
            "scheme round-trip restores the original https URL byte-for-byte")
    }

    func testCachingURLRejectsNonHTTP() {
        XCTAssertNil(CachingResourceLoaderDelegate.cachingURL(for: URL(string: "file:///tmp/x.mp3")!),
            "file:// URLs must not be routed through the caching loader")
        XCTAssertNil(CachingResourceLoaderDelegate.cachingURL(for: URL(string: "parsocache://x/y.mp3")!),
            "already-routed URLs are not re-wrapped")
    }

    func testParseTotalFromContentRange() {
        XCTAssertEqual(CachingResourceLoaderDelegate.parseTotal(fromContentRange: "bytes 0-0/12345"), 12345)
        XCTAssertEqual(CachingResourceLoaderDelegate.parseTotal(fromContentRange: "bytes 100-200/9999"), 9999)
        XCTAssertNil(CachingResourceLoaderDelegate.parseTotal(fromContentRange: "bytes 0-0/*"),
            "unknown-total (* form) is correctly rejected")
        XCTAssertNil(CachingResourceLoaderDelegate.parseTotal(fromContentRange: "garbage"))
    }

    func testUTIMappingForCommonAudio() {
        XCTAssertEqual(CachingResourceLoaderDelegate.uti(forMIME: "audio/mpeg", fallbackName: "x.mp3"), "public.mp3")
        XCTAssertEqual(CachingResourceLoaderDelegate.uti(forMIME: "audio/mp4", fallbackName: "x"), "com.apple.m4a-audio")
        XCTAssertEqual(CachingResourceLoaderDelegate.uti(forMIME: "audio/aac", fallbackName: "x.aac"), "com.apple.m4a-audio")
        XCTAssertEqual(CachingResourceLoaderDelegate.uti(forMIME: "audio/flac", fallbackName: "x.flac"), "org.xiph.flac")
        // Generic MIME → infer from filename.
        XCTAssertEqual(CachingResourceLoaderDelegate.uti(forMIME: "application/octet-stream",
                                                        fallbackName: "track.flac"), "org.xiph.flac")
        XCTAssertEqual(CachingResourceLoaderDelegate.uti(forMIME: "application/octet-stream",
                                                        fallbackName: "track"), "public.audio")
    }
}
