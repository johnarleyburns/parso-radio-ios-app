import Foundation

struct PodcastSearchResult: Identifiable, Codable {
    let id = UUID()
    let title: String
    let artist: String
    let feedURL: String
    let artworkURL: String?
    let trackCount: Int

    enum CodingKeys: String, CodingKey {
        case title = "collectionName"
        case artist = "artistName"
        case feedURL = "feedUrl"
        case artworkURL = "artworkUrl600"
        case trackCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decode(String.self, forKey: .artist)
        feedURL = try c.decode(String.self, forKey: .feedURL)
        artworkURL = try c.decodeIfPresent(String.self, forKey: .artworkURL)
        trackCount = try c.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
    }
}

final class PodcastSearchService {
    static let shared = PodcastSearchService()
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func search(term: String) async throws -> [PodcastSearchResult] {
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "entity", value: "podcast")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, _) = try await session.data(for: request)

        let wrapper = try JSONDecoder().decode(SearchResponse.self, from: data)
        return wrapper.results
    }
}

private struct SearchResponse: Decodable {
    let results: [PodcastSearchResult]
}
