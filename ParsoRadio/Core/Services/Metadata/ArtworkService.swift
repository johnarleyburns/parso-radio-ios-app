import Foundation
import UIKit
import AVFoundation
import CoreImage

@MainActor
final class ArtworkService {
    static let shared = ArtworkService()

    private let memCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 100
        c.totalCostLimit = 50 * 1024 * 1024
        return c
    }()

    // Sentinel stored in memCache to avoid repeated failed fetches
    private static let notFoundSentinel = UIImage()

    private let diskCacheDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("parso_music/artwork_cache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let session: URLSession = .app

    private init() {}

    // MARK: - Public API

    func artwork(for track: Track) async -> UIImage? {
        let key = track.id as NSString

        // 1. Memory cache
        if let cached = memCache.object(forKey: key) {
            return cached === Self.notFoundSentinel ? nil : cached
        }

        // 2. Disk cache
        if let image = readDiskCache(key: track.id) {
            store(image, forKey: key)
            return image
        }

        // 3. Fetch/extract
        let image: UIImage?
        if track.isLocal {
            image = await extractLocalArtwork(for: track)
        } else if let url = track.resolvedArtworkURL {
            image = await fetchRemoteArtwork(url: url, trackId: track.id)
        } else {
            image = nil
        }

        // 4. Cache result (or sentinel for not-found)
        if let image {
            store(image, forKey: key)
            writeDiskCache(image, key: track.id)
        } else {
            memCache.setObject(Self.notFoundSentinel, forKey: key)
        }
        return image
    }

    func artwork(fromURLString urlString: String?) async -> UIImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        // Check memory cache using the URL string as key
        let key = "url:\(urlString)" as NSString
        if let cached = memCache.object(forKey: key) {
            return cached === Self.notFoundSentinel ? nil : cached
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else {
            memCache.setObject(Self.notFoundSentinel, forKey: key)
            return nil
        }
        memCache.setObject(image, forKey: key)
        return image
    }

    func prefetch(_ tracks: [Track]) {
        Task { [weak self] in
            for track in tracks.prefix(20) {
                _ = await self?.artwork(for: track)
            }
        }
    }

    // Extract average (dominant) color using CIAreaAverage
    func dominantColor(from image: UIImage) -> UIColor {
        guard let ciImage = CIImage(image: image) else { return .systemBlue }
        let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: ciImage.extent)
            ]
        )
        guard let output = filter?.outputImage else { return .systemBlue }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    // MARK: - Private

    private func fetchRemoteArtwork(url: URL, trackId: String) async -> UIImage? {
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        // Detect IA "not found" redirect (final URL path ends in notfound.png)
        if let httpResponse = response as? HTTPURLResponse,
           let finalURL = httpResponse.url,
           finalURL.lastPathComponent == "notfound.png" { return nil }
        // Reject tiny responses (notfound image is ~800 bytes)
        guard data.count > 2048 else { return nil }
        return UIImage(data: data)
    }

    private func extractLocalArtwork(for track: Track) async -> UIImage? {
        guard let path = track.localFilePath else { return nil }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let metadata = try? await asset.load(.commonMetadata),
              let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }),
              let data = try? await item.load(.dataValue) else { return nil }
        return UIImage(data: data)
    }

    private func store(_ image: UIImage, forKey key: NSString) {
        let cost = Int(image.size.width * image.size.height * 4)
        memCache.setObject(image, forKey: key, cost: cost)
    }

    // MARK: - Disk cache (7-day TTL)

    private func diskCacheURL(key: String) -> URL {
        // FNV-1a hash to avoid filesystem issues with special characters in track IDs
        let hash = key.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        return diskCacheDir.appendingPathComponent(String(format: "%016llx.jpg", hash))
    }

    private func readDiskCache(key: String) -> UIImage? {
        let url = diskCacheURL(key: key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 7 * 86400,
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func writeDiskCache(_ image: UIImage, key: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: diskCacheURL(key: key))
    }
}
