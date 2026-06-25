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

    /// Quality rank for an MP3 format string. Higher is better. Used to pick the
    /// single best variant when an IA item ships the same chapter at multiple
    /// bitrates (64k/128k/VBR/…). Order: 320 > 256 > 192 > VBR > 128 > 64 > MP3.
    func bitrateRank(_ format: String?) -> Int {
        guard let f = format?.lowercased() else { return 0 }
        if f.contains("320") { return 6 }
        if f.contains("256") { return 5 }
        if f.contains("192") { return 4 }
        if f.contains("vbr") { return 3 }
        if f.contains("128") { return 2 }
        if f.contains("64")  { return 1 }
        return 0
    }

    /// Identity key that collapses multiple bitrate variants of the SAME chapter
    /// onto one group. Prefers the IA file `title` (LibriVox/IA expose a stable
    /// per-chapter title); otherwise the filename stem with trailing bitrate/
    /// quality tokens stripped.
    func chapterKey(filename: String, title: String?) -> String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return "t:" + t.lowercased()
        }
        var stem = (filename as NSString).deletingPathExtension.lowercased()
        let tokens = ["_320kbps", "_256kbps", "_192kbps", "_128kbps", "_64kbps",
                      "_320kb", "_256kb", "_192kb", "_128kb", "_64kb",
                      "-320kbps", "-256kbps", "-192kbps", "-128kbps", "-64kbps",
                      "-320kb", "-256kb", "-192kb", "-128kb", "-64kb",
                      "_vbr", "-vbr", "_320", "_256", "_192", "_128", "_64"]
        for tok in tokens { stem = stem.replacingOccurrences(of: tok, with: "") }
        stem = stem.replacingOccurrences(of: #"[ _-]+$"#, with: "",
                                         options: .regularExpression)
        return "f:" + stem
    }
}
