import Foundation

struct SourceValidator {
    private static let broadcastKeywords: [String] = [
        "pbs", "bbc", "cbc", "npr", "radio", "wnyc", "wbur", "kqed",
        "abc news", "cbs news", "nbc news", "fox news", "msnbc", "democracynow"
    ]

    static func isValid(_ track: Track, for channel: Channel) -> Bool {
        guard channel.feedURL == nil else { return true }
        let creator = track.rawCreator.lowercased()
        return !Self.broadcastKeywords.contains(where: { creator.contains($0) })
    }
}
