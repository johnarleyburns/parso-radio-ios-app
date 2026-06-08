import Foundation

struct TrackMetadata: Codable, Equatable {
    var trackID: String
    var mbRecordingID: String?
    var mbWorkID: String?
    var mbArtistID: String?
    var mbReleaseID: String?
    var composer: String?
    var composerMBID: String?
    var performer: String?
    var workTitle: String?
    var catalogNumber: String?
    var genreTags: [String]
    var durationMs: Int?
    var recordingDate: String?
    var composerPortraitURL: String?
    var albumArtURL: String?
    var trackArtURL: String?
    // Audiobook / author fields
    var author: String?
    var authorPortraitURL: String?
    var authorBio: String?
    var authorBirthDate: String?
    var authorDeathDate: String?
    var enrichedAt: TimeInterval
    var enrichmentSource: String?
}
