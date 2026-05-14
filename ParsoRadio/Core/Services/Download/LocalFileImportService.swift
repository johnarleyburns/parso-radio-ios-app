import Foundation
import AVFoundation
import UniformTypeIdentifiers

@MainActor
final class LocalFileImportService {
    private let db: DatabaseService
    private let fileStorage = FileStorageService()

    init(db: DatabaseService) { self.db = db }

    func importFile(at url: URL, intoPlaylist playlist: Playlist) async throws -> Track {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let track = try await processAudioFile(at: url)
        await db.addTrack(track, toPlaylist: playlist.id)
        return track
    }

    func importFolder(at url: URL, intoPlaylist playlist: Playlist) async throws -> [Track] {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let audioTypes: [UTType] = [.mp3, .mpeg4Audio, .aiff, .wav]
        var results: [Track] = []
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .contentTypeKey]),
                  resourceValues.isRegularFile == true,
                  let contentType = resourceValues.contentType,
                  audioTypes.contains(where: { contentType.conforms(to: $0) }) else { continue }
            if let track = try? await processAudioFile(at: fileURL) {
                await db.addTrack(track, toPlaylist: playlist.id)
                results.append(track)
            }
        }
        return results
    }

    private func processAudioFile(at url: URL) async throws -> Track {
        let destId = UUID().uuidString
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let baseURL = fileStorage.localURL(for: destId)
        let dest = baseURL.deletingPathExtension().appendingPathExtension(ext)
        let dir = dest.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: dest)

        let asset = AVURLAsset(url: dest)
        let metadata = try? await asset.load(.commonMetadata)

        let title = await metadataString(metadata, key: .commonKeyTitle)
            ?? url.deletingPathExtension().lastPathComponent
        let artist = await metadataString(metadata, key: .commonKeyArtist) ?? "Unknown"
        let durationValue = try? await asset.load(.duration)
        let duration = durationValue.map { $0.seconds } ?? 0

        let creationDate: Date? = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate

        let track = Track(
            id:                 destId,
            source:             "local",
            title:              title,
            artist:             artist,
            duration:           duration,
            streamURL:          dest,
            downloadURL:        nil,
            localFilePath:      dest.path,
            license:            .publicDomain,
            tags:               [],
            qualityScore:       0,
            rawCreator:         artist,
            composer:           nil,
            instruments:        [],
            metadataConfidence: 0,
            addedDate:          creationDate,
            isLocal:            true,
            partNumber:         nil,
            totalParts:         nil,
            parentIdentifier:   nil,
            artworkURLString:   nil
        )
        await db.saveTracks([track])
        // Artwork is extracted lazily by ArtworkService on first display
        return track
    }

    private func metadataString(_ metadata: [AVMetadataItem]?, key: AVMetadataKey) async -> String? {
        guard let item = metadata?.first(where: { $0.commonKey == key }) else { return nil }
        return try? await item.load(.stringValue)
    }
}
