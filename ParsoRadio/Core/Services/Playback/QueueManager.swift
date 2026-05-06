import Foundation

struct QueueManager {
    func nextTrack(channel: Channel, from tracks: [Track]) -> Track? {
        tracks.filter { channel.matches($0) }.first
    }
}
