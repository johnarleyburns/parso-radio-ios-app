import Foundation

/// Public-facing URL we hand to the system share sheet. Internet Archive
/// tracks share their `archive.org/details/<identifier>` page (so the
/// recipient can preview in a browser); other sources fall back to the
/// direct stream URL. Local imports and ambient placeholders aren't
/// shareable.
///
/// Builds a share URL for a track; unit-tested in isolation.
enum ShareURLBuilder {
    static func url(for track: Track) -> URL? {
        guard !track.isLocal else { return nil }
        switch track.source {
        case "internet_archive":
            let identifier: String
            if let parent = track.parentIdentifier { identifier = parent }
            else if let prefix = track.id.split(separator: "/").first { identifier = String(prefix) }
            else { identifier = track.id }
            return URL(string: "https://archive.org/details/\(identifier)")
        case "ambient":
            return nil
        default:
            return track.streamURL
        }
    }
}
