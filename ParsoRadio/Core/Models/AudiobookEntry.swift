import Foundation

struct AudiobookEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String            // IA identifier
    let title: String?
    let creator: String?
    let date: String?
    let downloads: Int
    let description: String?  // Rich description from IA metadata

    var displayName: String {
        title ?? id
    }

    var author: String {
        creator ?? "Unknown Author"
    }

    var formattedDate: String? {
        guard let date else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let d = df.date(from: date) {
            df.dateFormat = "MMMM d, yyyy"
            return df.string(from: d)
        }
        df.dateFormat = "yyyy-MM-dd"
        if let d = df.date(from: String(date.prefix(10))) {
            df.dateFormat = "MMMM d, yyyy"
            return df.string(from: d)
        }
        return date
    }

    var thumbnailURL: URL {
        URL(string: "https://archive.org/services/img/\(id)")!
    }

    /// Match audiobook keywords to an existing lv-* category image.
    var categoryImageName: String? {
        let haystack = (displayName + " " + (description ?? "")).lowercased()
        let mappings: [(String, [String])] = [
            ("lv-science-fiction", ["science fiction", "sci-fi", "space"]),
            ("lv-fantasy-mythology", ["fantasy", "mythology", "fairy"]),
            ("lv-mystery-crime", ["mystery", "crime", "detective", "sherlock"]),
            ("lv-horror-gothic", ["horror", "gothic", "ghost", "vampire"]),
            ("lv-romance", ["romance", "love", "romantic"]),
            ("lv-adventure", ["adventure", "exploration"]),
            ("lv-history", ["history", "historical"]),
            ("lv-biography", ["biography", "autobiography", "memoir"]),
            ("lv-philosophy-mind", ["philosophy", "mind", "thought"]),
            ("lv-science-nature", ["science", "nature", "natural"]),
            ("lv-religion", ["religion", "bible", "scripture", "god"]),
            ("lv-poetry", ["poem", "poetry", "verse"]),
            ("lv-drama-plays", ["drama", "play", "theatre", "theater"]),
            ("lv-short-stories", ["short story", "short stories", "tales"]),
            ("lv-essays-ideas", ["essay", "essays", "idea", "philosophy"]),
            ("lv-war-military", ["war", "military", "battle"]),
            ("lv-travel", ["travel", "journey", "voyage"]),
            ("lv-literary-fiction", ["literary", "classic", "novel"]),
        ]
        for (imageName, keywords) in mappings {
            if keywords.contains(where: { haystack.contains($0) }) {
                return imageName
            }
        }
        return nil
    }
}
