import Foundation

struct PlaybackContext {
    enum Origin: String {
        case channel
        case playlist
        case directItem
        case search
        case madeForYou
        case bookForYou
        case liveMusic
        case audition
        case recentlyPlayed
    }

    let origin: Origin
    let mediaKind: MediaKind
    let title: String
    let channelId: String?
    let playlistId: String?
    var persistsResumePosition: Bool
    var contentMode: AudioPlayerService.ContentMode

    init(origin: Origin, mediaKind: MediaKind, title: String, channelId: String? = nil, playlistId: String? = nil) {
        self.origin = origin
        self.mediaKind = mediaKind
        self.title = title
        self.channelId = channelId
        self.playlistId = playlistId
        self.persistsResumePosition = mediaKind == .audiobook || mediaKind == .lecture
        self.contentMode = (mediaKind == .audiobook || mediaKind == .lecture || mediaKind == .podcast) ? .spokenWord : .music
    }
}
