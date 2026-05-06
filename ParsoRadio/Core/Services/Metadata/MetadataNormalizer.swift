import Foundation

struct MetadataNormalizer {
    private let detector = InstrumentDetector()

    func normalize(
        creator: String?,
        title: String?,
        subjects: [String],
        description: String?,
        licenseURL: String?,
        year: Int?,
        duration: Double?
    ) -> (composer: String?, instruments: [String], confidence: Double) {
        let composer = creator.flatMap { ComposerMap.normalize($0) }
        let instruments = detector.detect(
            title: title ?? "",
            subjects: subjects,
            description: description
        )

        var quality = 0.0
        if licenseURL != nil { quality += 0.3 }
        if !subjects.isEmpty { quality += 0.3 }
        if duration != nil { quality += 0.2 }
        if year != nil { quality += 0.2 }

        let confidence = (composer != nil ? 2.0 : 0.0)
            + (instruments.isEmpty ? 0.0 : 1.0)
            + quality

        return (composer, instruments, confidence)
    }
}
