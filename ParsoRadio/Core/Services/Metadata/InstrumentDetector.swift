import Foundation

struct InstrumentDetector {
    private static let stringKeywords = [
        "violin", "cello", "viola", "string quartet", "string orchestra",
        "concerto for strings", "strings", "fiddle", "violoncello",
        "Brandenburg", "Four Seasons",
    ]

    private static let pianoKeywords = [
        "piano", "pianoforte", "nocturne", "étude", "etude", "ballade",
        "piano concerto", "piano sonata", "piano trio",
        "prelude for piano", "waltz for piano",
    ]

    func detect(title: String, subjects: [String], description: String?) -> [String] {
        let corpus = ([title] + subjects + [description ?? ""]).joined(separator: " ").lowercased()
        var found: [String] = []
        if Self.stringKeywords.contains(where: { corpus.contains($0.lowercased()) }) {
            found.append("strings")
        }
        if Self.pianoKeywords.contains(where: { corpus.contains($0.lowercased()) }) {
            found.append("piano")
        }
        return found
    }
}
