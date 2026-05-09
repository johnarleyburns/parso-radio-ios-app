import Foundation

struct FileStorageService {
    func localURL(for trackID: String) -> URL {
        // Strip any character that isn't alphanumeric, hyphen, underscore, or dot.
        // Prevents path traversal (e.g. "../../../etc") if an upstream source is compromised.
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_."))
        let safe = String(trackID.unicodeScalars.filter { allowed.contains($0) }.prefix(200))
        let filename = (safe.isEmpty ? "track" : safe) + ".mp3"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent(filename)
    }
}
