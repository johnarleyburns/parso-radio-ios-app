import SwiftUI

enum MenuRoute: Hashable {
    case playlist(Playlist)
    case channelInfo(Channel)
    case recentlyPlayed
    case settings
}
