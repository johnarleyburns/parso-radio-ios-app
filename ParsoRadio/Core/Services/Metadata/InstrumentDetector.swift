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

    private static let woodwindKeywords = [
        "flute", "oboe", "clarinet", "bassoon", "saxophone", "piccolo",
        "recorder", "woodwind", "wind quartet", "wind quintet",
    ]

    private static let brassKeywords = [
        "trumpet", "trombone", "horn", "tuba", "cornet", "flugelhorn",
        "brass quartet", "brass quintet", "brass ensemble",
    ]

    private static let percussionKeywords = [
        "timpani", "percussion", "marimba", "xylophone", "vibraphone",
        "snare drum", "kettle drum",
    ]

    private static let pluckedKeywords = [
        "lute", "theorbo", "harp", "mandolin", "viola da gamba",
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
        if Self.woodwindKeywords.contains(where: { corpus.contains($0.lowercased()) }) {
            found.append("woodwind")
        }
        if Self.brassKeywords.contains(where: { corpus.contains($0.lowercased()) }) {
            found.append("brass")
        }
        if Self.percussionKeywords.contains(where: { corpus.contains($0.lowercased()) }) {
            found.append("percussion")
        }
        if Self.pluckedKeywords.contains(where: { corpus.contains($0.lowercased()) }) {
            found.append("plucked")
        }
        return found
    }
}
