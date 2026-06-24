import Foundation

struct MP3AudioFormatSelector {

    private static let acceptedFormats: Set<String> = [
        "VBR MP3", "128Kbps MP3", "64Kbps MP3", "256Kbps MP3",
        "320Kbps MP3", "192Kbps MP3", "MP3", "MPEG Audio Layer 3"
    ]

    private static let acceptedExtensions: Set<String> = ["mp3"]

    func isAcceptedFormat(_ format: String?) -> Bool {
        guard let format else { return false }
        for accepted in Self.acceptedFormats {
            if format == accepted || format.hasSuffix(accepted) {
                return true
            }
        }
        return false
    }

    func isAcceptedFormatByExtension(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return Self.acceptedExtensions.contains(ext)
    }

    func heuristicAcceptsFormat(_ format: String?) -> Bool {
        guard let format else { return false }
        let lower = format.lowercased()
        if lower.contains("mp3") { return true }
        return false
    }

    func isAcceptedByAnyRule(format: String?, filename: String) -> Bool {
        if isAcceptedFormat(format) { return true }
        if isAcceptedFormatByExtension(filename) { return true }
        return false
    }
}
