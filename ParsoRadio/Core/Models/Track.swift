import Foundation

struct Track: Codable, Identifiable {
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
}
