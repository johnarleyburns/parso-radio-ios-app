import Foundation

struct FileStorageService {
    func localURL(for trackID: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio/\(trackID).mp3")
    }
}
