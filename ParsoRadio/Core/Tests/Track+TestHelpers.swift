import Foundation
@testable import ParsoMusic

extension Track {
    static func makeStub(id: String, title: String, parentIdentifier: String? = nil) -> Track {
        Track(
            id: id,
            source: "test",
            title: title,
            artist: "Test Artist",
            duration: 180,
            streamURL: URL(string: "https://example.com/\(id).mp3")!,
            downloadURL: nil,
            localFilePath: nil,
            license: .publicDomain,
            tags: [],
            qualityScore: 3.0,
            rawCreator: "Test Artist",
            composer: nil,
            instruments: [],
            metadataConfidence: 1.0,
            parentIdentifier: parentIdentifier
        )
    }
}
