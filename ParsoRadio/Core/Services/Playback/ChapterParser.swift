import Foundation
import AVFoundation

enum ChapterParser {
    static func parse(from playerItem: AVPlayerItem?) -> [Chapter] {
        guard let playerItem else { return [] }
        let asset = playerItem.asset

        var chapters: [Chapter] = []

        if #available(iOS 16.0, *) {
            let locale = Locale(identifier: "en")
            let groups = asset.chapterMetadataGroups(bestMatchingPreferredLanguages: [locale.identifier])
            for group in groups {
                let title = group.items.first(where: {
                    $0.commonKey == .commonKeyTitle
                })?.stringValue ?? (group.items.first?.stringValue ?? "")

                let timeRange = group.timeRange
                let startTime: Double = timeRange.start.seconds
                let duration: Double = timeRange.duration.isNumeric ? timeRange.duration.seconds : 0

                if !title.trimmingCharacters(in: .whitespaces).isEmpty {
                    chapters.append(Chapter(title: title, startTime: startTime, duration: duration))
                }
            }
        }

        if chapters.isEmpty {
            chapters = parseFromMetadataItems(asset.metadata)
        }

        return chapters.sorted { $0.startTime < $1.startTime }
    }

    private static func parseFromMetadataItems(_ items: [AVMetadataItem]) -> [Chapter] {
        struct RawChapter {
            let title: String
            let startTime: Double
            let duration: Double
        }

        var raw: [RawChapter] = []

        for item in items {
            guard let key = item.commonKey else { continue }

            let title: String
            if key == .commonKeyTitle, let t = item.stringValue, !t.trimmingCharacters(in: .whitespaces).isEmpty {
                title = t
            } else {
                continue
            }

            let time = item.time.seconds
            let dur = item.duration.isNumeric ? item.duration.seconds : 0

            // Filter out non-chapter metadata (duration > 0 helps distinguish)
            if time > 0 || dur > 0 {
                raw.append(RawChapter(title: title, startTime: time, duration: dur))
            }
        }

        // If we didn't find timed chapters, try to read the text-based chapter list
        var result: [Chapter] = []

        let sorted = raw.sorted { $0.startTime < $1.startTime }

        for (i, r) in sorted.enumerated() {
            let nextStart = i + 1 < sorted.count ? sorted[i + 1].startTime : nil
            let dur = r.duration > 0 ? r.duration : (nextStart.map { $0 - r.startTime } ?? 0)
            result.append(Chapter(title: r.title, startTime: r.startTime, duration: max(0, dur)))
        }

        return result
    }
}
