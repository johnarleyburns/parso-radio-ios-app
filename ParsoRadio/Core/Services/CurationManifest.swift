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

    /// A channel's approved tracks as a playable pool ([] if none shipped).
    func pool(for channelId: String) -> [Track] {
        (manifest?.approved(for: channelId) ?? []).map { $0.asTrack() }
    }
}

/// The LIVE curation store on the curator's device: every `setCuration` call
/// triggers a `reload(from:)` which (1) rebuilds the in-memory approved-per-
/// channel snapshot QueueManager reads from, and (2) atomically writes the
/// current manifest to `Documents/curation.json`. So the curator sees their
/// own verdicts take effect on playback immediately, AND the file is right
/// there in the iOS Files app for inspection / sharing without an app
/// rebuild. Falls back to the SHIPPED bundled manifest for any channel the
/// curator hasn't touched (non-curator users on the App Store).
final class LiveCurationStore {
    static let shared = LiveCurationStore()

    private let lock = NSLock()
    private var approvedByChannel: [String: [Track]] = [:]

    /// Re-read curated tracks from the DB; refresh the in-memory snapshot.
    /// The DB is the sole source of truth. JSON files are for import/export
    /// only — they are NEVER written to by runtime verdicts.
    func reload(from db: DatabaseService) async {
        let approved = await db.exportApprovedByChannel()
        lock.withLock {
            approvedByChannel = approved
        }
    }

    /// QueueManager calls this on every track pick. Prefers the curator's live
    /// DB; falls back to the BUNDLED manifest (so non-curator users still play
    /// the shipped curation).
    func pool(for channelId: String) -> [Track] {
        // The DB is the sole source of truth for all curation verdicts.
        // JSON files are for import/export/sharing only — NEVER for runtime
        // playback decisions. This prevents stale-file bugs where a rejected
        // track in the DB would still play because the JSON file had it.
        lock.withLock { approvedByChannel[channelId] ?? [] }
    }

    /// True if the live DB has any approved tracks for this channel.
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
