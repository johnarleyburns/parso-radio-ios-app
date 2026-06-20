import Foundation

struct LiveMusicEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let creator: String
    let title: String?
    let venue: String?
    let coverage: String?
    let date: String?
    let year: Int?
    let downloads: Int
    let dateString: String
    let description: String?

    var displayName: String {
        title ?? creator
    }

    var hasTitle: Bool {
        title != nil
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

    init(
        id: String,
        creator: String,
        title: String? = nil,
        venue: String? = nil,
        coverage: String? = nil,
        date: String? = nil,
        year: Int? = nil,
        downloads: Int = 0,
        dateString: String,
        description: String? = nil
    ) {
        self.id = id
        self.creator = creator
        self.title = title
        self.venue = venue
        self.coverage = coverage
        self.date = date
        self.year = year
        self.downloads = downloads
        self.dateString = dateString
        self.description = description
    }
}
