import Foundation

struct DatabaseService {
    func saveTracks(_ tracks: [Track]) {}
    func fetchTracks(forChannel channel: Channel) -> [Track] { [] }
    func markDownloaded(trackID: String, localPath: String) {}
    func fetchDownloadedTracks(forChannel channel: Channel) -> [Track] { [] }
}
