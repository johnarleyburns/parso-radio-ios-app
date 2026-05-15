import Foundation

struct IAQueryEntry: Decodable {
    let channelId: String
    let iaQuery: String
    let matchTags: [String]
}

final class IAQueryRegistry {
    static let shared = IAQueryRegistry()
    private var entries: [String: IAQueryEntry] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "ia_queries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([IAQueryEntry].self, from: data) else { return }
        entries = Dictionary(uniqueKeysWithValues: list.map { ($0.channelId, $0) })
    }

    func entry(for channelId: String) -> IAQueryEntry? { entries[channelId] }
}
