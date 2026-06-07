import Foundation
import Combine

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

    /// A channel's approved tracks as a playable pool ([] if none shipped).
    func pool(for channelId: String) -> [Track] {
        (manifest?.approved(for: channelId) ?? []).map { $0.asTrack() }
    }
}

/// The LIVE curation store on the curator's device. ObservableObject so
/// SwiftUI views automatically refresh when verdicts change.
final class LiveCurationStore: ObservableObject {
    static let shared = LiveCurationStore()

    private let lock = NSLock()
    @Published private var approvedByChannel: [String: [Track]] = [:]

    func reload(from db: DatabaseService) async {
        let approved = await db.exportApprovedByChannel()
        lock.withLock {
            approvedByChannel = approved
        }
        await MainActor.run { [approved] in
            self.approvedByChannel = approved
        }
    }

    func pool(for channelId: String) -> [Track] {
        lock.withLock { approvedByChannel[channelId] ?? [] }
    }

    func hasLiveCuration(for channelId: String) -> Bool {
        lock.withLock {
            !(approvedByChannel[channelId]?.isEmpty ?? true)
        }
    }
}

extension CurationManifest.Entry {
    /// Turn a manifest entry into a playable Track. The streamURL is the IA
    /// download endpoint (per-file ids are already direct; item ids are resolved
    /// at play time by PlayerViewModel exactly as for any IA track).
    func asTrack() -> Track {
        Track(
            id: id,
            source: "internet_archive",
            title: title,
            artist: creator,
            duration: duration,
            streamURL: URL(string: "https://archive.org/download/\(id)")
                ?? URL(string: "https://archive.org")!,
            downloadURL: nil,
            localFilePath: nil,
            license: .publicDomain,
            tags: [],
            qualityScore: 1.0,
            rawCreator: creator,
            composer: nil,
            instruments: [],
            metadataConfidence: 1.0,
            parentIdentifier: parentIdentifier
        )
    }
}
