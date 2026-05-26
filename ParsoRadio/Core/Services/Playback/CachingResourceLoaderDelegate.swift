import AVFoundation
import Foundation

/// AVAssetResourceLoader delegate that streams a remote audio file through the
/// tested ContiguousFileCache: sequential playback grows the on-disk prefix,
/// seeks past it fall back to plain network. EXPERIMENTAL — gated by
/// UserDefaults("parso.useCachingPlayer"), default off. See PLAYBACK-DESIGN.md.
///
/// All decision logic that CAN be unit-tested already is (ContiguousFileCache,
/// SourceSelector, CacheEvictionPolicy, InFlightRegistry). This file is the
/// AVFoundation glue that drives them and only it requires on-device validation.
final class CachingResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    /// Custom URL scheme that routes asset requests to this delegate.
    static let scheme = "parsocache"

    private let originalURL: URL
    private let cache: ContiguousFileCache
    private let session: URLSession

    init(originalURL: URL, cache: ContiguousFileCache) {
        self.originalURL = originalURL
        self.cache = cache
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 3600  // long enough for a whole audiobook
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    deinit {
        session.invalidateAndCancel()
        cache.close()
    }

    /// Swap a remote URL's scheme to the custom one so the asset's resource
    /// loader routes through this delegate. Only http/https are wrapped; other
    /// schemes (file://, parsocache://) are passed through unchanged by returning
    /// nil so the caller can fall back to a plain AVPlayerItem(url:).
    static func cachingURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = Self.scheme
        return comps.url
    }

    /// Recover the original URL from a `parsocache://…` URL (the original scheme
    /// is restored — https by default, which is what every source uses).
    static func originalURL(from cachingURL: URL, originalScheme: String = "https") -> URL? {
        guard var comps = URLComponents(url: cachingURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = originalScheme
        return comps.url
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource req: AVAssetResourceLoadingRequest) -> Bool {
        Task { [weak self] in await self?.handle(req) }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // The in-flight Task completes naturally; AVFoundation ignores a
        // finishLoading() call on an already-cancelled request.
    }

    // MARK: - Handling

    private func handle(_ req: AVAssetResourceLoadingRequest) async {
        do {
            if let info = req.contentInformationRequest {
                let probe = try await probeContentInfo()
                info.contentType = probe.uti
                info.contentLength = probe.length
                info.isByteRangeAccessSupported = true
                cache.setContentLength(probe.length)
            }
            if let dr = req.dataRequest {
                try await serve(dr)
            }
            req.finishLoading()
        } catch is CancellationError {
            // request cancelled — silent.
        } catch {
            req.finishLoading(with: error)
        }
    }

    // MARK: - Content-info probe

    private struct ContentProbe { let length: Int64; let uti: String }

    private func probeContentInfo() async throws -> ContentProbe {
        // A ranged GET of byte 0 returns 206 with `Content-Range: bytes 0-0/<total>`
        // — the most reliable way to learn the total length (HEAD often doesn't
        // populate Content-Length on archive.org's CDN redirects).
        var req = URLRequest(url: originalURL)
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.cannotParseResponse) }
        let length: Int64
        if let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let total = Self.parseTotal(fromContentRange: cr) {
            length = total
        } else if http.expectedContentLength > 0 {
            length = http.expectedContentLength
        } else {
            throw URLError(.zeroByteResource)
        }
        let mime = http.value(forHTTPHeaderField: "Content-Type") ?? "audio/mpeg"
        return ContentProbe(length: length,
                            uti: Self.uti(forMIME: mime, fallbackName: originalURL.lastPathComponent))
    }

    /// Parse the total length out of `"bytes 0-0/123456"`. Returns nil for the
    /// unknown-total form (`bytes 0-0/*`).
    static func parseTotal(fromContentRange v: String) -> Int64? {
        guard let slash = v.lastIndex(of: "/") else { return nil }
        let totalStr = v[v.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        return Int64(totalStr)
    }

    /// Map a MIME type (or fallback file extension) to a UTI that
    /// AVAssetResourceLoadingContentInformationRequest.contentType accepts.
    static func uti(forMIME mime: String, fallbackName: String) -> String {
        let m = mime.lowercased()
        if m.contains("mpeg") && !m.contains("mp4") { return "public.mp3" }
        if m.contains("mp3") { return "public.mp3" }
        if m.contains("mp4") || m.contains("m4a") || m.contains("aac") { return "com.apple.m4a-audio" }
        if m.contains("ogg") { return "org.xiph.ogg-vorbis" }
        if m.contains("flac") { return "org.xiph.flac" }
        if m.contains("wav") { return "com.microsoft.waveform-audio" }
        switch (fallbackName as NSString).pathExtension.lowercased() {
        case "mp3":         return "public.mp3"
        case "m4a", "aac":  return "com.apple.m4a-audio"
        case "ogg":         return "org.xiph.ogg-vorbis"
        case "flac":        return "org.xiph.flac"
        case "wav":         return "com.microsoft.waveform-audio"
        default:            return "public.audio"
        }
    }

    // MARK: - Data serving

    private func serve(_ dr: AVAssetResourceLoadingDataRequest) async throws {
        var cursor = dr.currentOffset

        // 1) Drain any cached prefix that overlaps the requested range first.
        if cursor < cache.cachedLength {
            let endRequested: Int64
            if dr.requestsAllDataToEndOfResource {
                endRequested = cache.contentLength ?? cache.cachedLength
            } else {
                endRequested = dr.requestedOffset + Int64(dr.requestedLength)
            }
            let upto = min(endRequested, cache.cachedLength)
            let span = Int(upto - cursor)
            if span > 0, let data = cache.read(offset: cursor, length: span) {
                dr.respond(with: data)
                cursor = upto
            }
        }

        try Task.checkCancellation()

        // 2) Anything left → fetch from the network and feed AVPlayer
        // PROGRESSIVELY in chunks so it can start playing before the whole
        // range arrives. The previous URLSession.data(for:) wait-for-full-body
        // was the "Buffering forever" bug: a 15 MB audiobook chapter delivered
        // zero bytes to AVPlayer until the whole file downloaded.
        let rangeHeader: String
        let endNeeded: Int64
        if dr.requestsAllDataToEndOfResource {
            endNeeded = cache.contentLength ?? Int64.max
            // Prefer a CLOSED range when we know the length (some CDNs handle
            // closed ranges more reliably than open `bytes=N-`).
            if let cl = cache.contentLength, cl > cursor {
                rangeHeader = "bytes=\(cursor)-\(cl - 1)"
            } else {
                rangeHeader = "bytes=\(cursor)-"
            }
        } else {
            endNeeded = dr.requestedOffset + Int64(dr.requestedLength)
            guard cursor < endNeeded else { return }
            rangeHeader = "bytes=\(cursor)-\(endNeeded - 1)"
        }
        guard cursor < endNeeded else { return }

        var request = URLRequest(url: originalURL)
        request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        let (bytes, _) = try await session.bytes(for: request)

        // 32 KB chunks: AVPlayer starts playing within a few hundred ms of the
        // first chunk on broadband, and the per-byte iteration overhead is
        // amortised across the chunk.
        let chunkSize = 32 * 1024
        var buf: [UInt8] = []
        buf.reserveCapacity(chunkSize)
        for try await byte in bytes {
            buf.append(byte)
            if buf.count >= chunkSize {
                try Task.checkCancellation()
                let chunk = Data(buf)
                cache.appendContiguous(chunk, at: cursor)
                dr.respond(with: chunk)
                cursor += Int64(chunk.count)
                buf.removeAll(keepingCapacity: true)
            }
        }
        if !buf.isEmpty {
            let chunk = Data(buf)
            cache.appendContiguous(chunk, at: cursor)
            dr.respond(with: chunk)
            cursor += Int64(chunk.count)
        }
    }
}
