import Foundation

/// The SHIPPED curation (`ParsoRadio/Resources/curation.json`): the human-approved
/// tracks per curated channel. Authored in Curator Mode → exported → committed →
/// bundled. At runtime it becomes a curated channel's play pool (a channel with
/// an entry plays approved-only; a channel without one keeps its search pool, so
/// conversion is channel-by-channel). See CURATOR-MODE-PLAN.md.
struct CurationManifest: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let id: String                 // identifier, or "identifier/file"
        let title: String
        let creator: String
        let duration: Double
        let parentIdentifier: String?
    }
    struct ChannelCuration: Codable, Equatable {
        let updatedAt: String?
        let approved: [Entry]
    }
    let version: Int
    let channels: [String: ChannelCuration]

    func approved(for channelId: String) -> [Entry] {
        channels[channelId]?.approved ?? []
    }
}

/// Loads the bundled curation manifest once (like IAQueryRegistry).
final class CurationManifestStore {
    static let shared = CurationManifestStore()
    let manifest: CurationManifest?

    private init() {
        manifest = Self.loadBundled()
    }

    static func loadBundled() -> CurationManifest? {
        guard let url = Bundle.main.url(forResource: "curation", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(CurationManifest.self, from: data)
        else { return nil }
        return m
    }

    /// True once a channel has shipped, non-empty curation → play approved-only.
    func hasCuration(for channelId: String) -> Bool {
        !(manifest?.approved(for: channelId).isEmpty ?? true)
    }
}
