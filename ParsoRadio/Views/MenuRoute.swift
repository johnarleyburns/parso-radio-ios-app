import SwiftUI

enum MenuRoute: Hashable {
    case playlist(Playlist)
    case channelInfo(Channel)
    case channelList(String)
    case playlists
    case recentlyPlayed
    case settings
}
