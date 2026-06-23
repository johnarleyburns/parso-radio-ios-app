import Foundation

struct BundledBook: Codable, Equatable, Sendable {
    let identifier: String
    let title: String
    let author: String
    let subjects: [String]
    let downloads: Int
    let work_key: String

    func toCandidate() -> BookCandidate {
        BookCandidate(
            identifier: identifier,
            title: title,
            creator: author,
            subjects: subjects,
            downloads: downloads
        )
    }
}

enum LibrivoxBundledBooks {
    private static var _cache: [BundledBook]?

    /// Lazy-loaded from the bundled JSON resource. Cached in memory after first load.
    static var all: [BundledBook] {
        if let cache = _cache { return cache }
        guard let url = Bundle.main.url(forResource: "bundled_books",
                                        withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let books = try? JSONDecoder().decode([BundledBook].self, from: data)
        else {
            _cache = []
            return []
        }
        _cache = books
        return books
    }

    /// Convert bundled books to BookCandidate pool for use in the service.
    static var candidates: [BookCandidate] {
        all.map { $0.toCandidate() }
    }

    /// Pick one at random using a date seed for stability.
    static func pick(seed: String) -> BookCandidate? {
        BookForYouService.choose(from: candidates, seed: seed)
    }
}
