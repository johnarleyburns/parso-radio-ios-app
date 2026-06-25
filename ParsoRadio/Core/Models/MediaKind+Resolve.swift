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

    /// Channel-free media-kind classification used when no live channel context
    /// is available (history backfill, direct/search plays, defensive shelf
    /// filtering). Reads the persisted `source` plus the channel-isolation stamp
    /// tags (`pmreg::<channelId>`) that registry fetches inject onto the track:
    /// `lv-*` → audiobook, `oxford-*` → lecture, `podcast-*`/`news-*` → podcast.
    /// Falls back to `.music`, which is correct for plain Internet Archive music.
    var inferredMediaKind: MediaKind {
        if source == "podcast" { return .podcast }
        if source == "oxford_lectures" { return .lecture }
        let stamps = tags.map { tag -> String in
            tag.hasPrefix("pmreg::") ? String(tag.dropFirst("pmreg::".count)) : tag
        }
        if stamps.contains(where: { $0.hasPrefix("lv-") }) { return .audiobook }
        if stamps.contains(where: { $0.hasPrefix("oxford-") }) { return .lecture }
        if stamps.contains(where: { $0.hasPrefix("podcast-") || $0.hasPrefix("news-") }) { return .podcast }
        return .music
    }
}
