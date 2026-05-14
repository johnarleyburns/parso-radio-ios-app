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
    let tags: [String]
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
}

extension Track {
    var resolvedArtworkURL: URL? {
        if source == "internet_archive" {
            return URL(string: "https://archive.org/services/img/\(id)")
        }
        return artworkURLString.flatMap(URL.init)
    }

    var displayDate: Date? {
        if let d = addedDate { return d }
        if qualityScore > 1_000_000_000 { return Date(timeIntervalSince1970: qualityScore) }
        return nil
    }
}
