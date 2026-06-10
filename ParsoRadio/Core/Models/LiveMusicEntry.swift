import Foundation

struct LiveMusicEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String            // IA identifier
    let creator: String
    let title: String?        // Full recording title from IA metadata
    let venue: String?
    let coverage: String?     // Location (city, state) from IA metadata
    let date: String?         // Raw date string (e.g. "2023-06-09")
    let year: Int?
    let downloads: Int
    let dateString: String    // MM-DD that produced this entry
    let description: String?  // Rich description from IA metadata

    var displayName: String {
        title ?? creator
    }

    var formattedDate: String? {
        guard let date else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        guard let d = df.date(from: String(date.prefix(10))) else { return date }
        df.dateFormat = "MMMM d, yyyy"
        return df.string(from: d)
    }

    var locationSummary: String? {
        if let coverage, let venue { return "\(venue) — \(coverage)" }
        return venue ?? coverage
    }

    var thumbnailURL: URL {
        URL(string: "https://archive.org/services/img/\(id)")!
    }
}
