import Foundation

extension Channel {
    var mediaKind: MediaKind {
        if contentType == .ambientLoop || category == "Ambient" { return .ambient }
        if feedURL != nil || preferredSource == "podcast" { return .podcast }
        if preferredSource == "oxford_lectures" || category == "Lectures" { return .lecture }
        if category == "Audiobooks" { return .audiobook }
        if contentType == .spokenWord {
            return .audiobook
        }
        return .music
    }

    var behavior: PlaybackBehavior { mediaKind.behavior }
}

extension Track {
    func mediaKind(in channel: Channel?) -> MediaKind {
        if source == "podcast" { return .podcast }
        if source == "oxford_lectures" { return .lecture }
        if let cat = channel?.category,
           cat == "Audiobooks" {
            return .audiobook
        }
        if parentIdentifier != nil,
           channel?.contentType == .spokenWord {
            return .audiobook
        }
        return .music
    }
}
