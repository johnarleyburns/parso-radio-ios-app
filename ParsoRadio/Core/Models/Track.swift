import Foundation

struct Track: Codable, Identifiable {
    // Existing fields
    let id: String
    let source: String
    let title: String
    let artist: String
    let duration: Double
    let streamURL: URL
    let downloadURL: URL?
    var localFilePath: String?
    let license: LicenseType
    var tags: [String]
    let qualityScore: Double
    let rawCreator: String
    let composer: String?
    let instruments: [String]
    let metadataConfidence: Double

    // New fields — all optional/defaulted so existing DB rows decode without error
    var addedDate: Date? = nil
    var isLocal: Bool = false
    var partNumber: Int? = nil
    var totalParts: Int? = nil
    var parentIdentifier: String? = nil
    var artworkURLString: String? = nil
    // Original recording/publication date when the source exposes one
    // (IA `date`/`year`). Distinct from addedDate (upload date).
    var recordingDate: Date? = nil
}

extension Track {
    var resolvedArtworkURL: URL? {
        if source == "internet_archive" {
            return URL(string: "https://archive.org/services/img/\(id)")
        }
        return artworkURLString.flatMap(URL.init)
    }

    // Prefer the original recording/publication date; fall back to the
    // upload date. `dateLabel` tells the UI which one it is.
    var bestDate: Date? { recordingDate ?? displayDate }
    var dateLabel: String { recordingDate != nil ? "Recorded" : "Added" }

    // Imported local files live in Documents/audio/. The app's sandbox
    // container path changes across launches, so a stored ABSOLUTE path goes
    // stale and playback silently fails. Resolve by filename against the
    // CURRENT Documents dir instead — backward-compatible with rows that
    // stored an absolute path (we only use its last component).
    var resolvedLocalURL: URL? {
        guard isLocal || source == "local", let stored = localFilePath else { return nil }
        let name = (stored as NSString).lastPathComponent
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var displayDate: Date? {
        if let d = addedDate { return d }
        if qualityScore > 1_000_000_000 { return Date(timeIntervalSince1970: qualityScore) }
        return nil
    }

    // Stamp channel-isolation tags onto a track. Registry channels match by these
    // injected tags (not by IA subject), so a track fetched by an ia_queries.json
    // query is reliably isolated to its channel even when the IA item has sparse
    // or missing subject metadata.
    func stamped(with extraTags: [String]) -> Track {
        guard !extraTags.isEmpty else { return self }
        var copy = self
        copy.tags = copy.tags + extraTags.filter { !copy.tags.contains($0) }
        return copy
    }
}
