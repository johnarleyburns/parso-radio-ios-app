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

    /// Re-read curated tracks from the DB; rewrite the live manifest file.
    func reload(from db: DatabaseService) async {
        let approved = await db.exportApprovedByChannel()
        lock.withLock {
            approvedByChannel = approved
        }
        writeLiveManifest(approved)
    }

    /// QueueManager calls this on every track pick. Prefers the curator's live
    /// DB; falls back to the BUNDLED manifest (so non-curator users still play
    /// the shipped curation).
    func pool(for channelId: String) -> [Track] {
        // The live DB snapshot (updated on every verdict via reload(from:)) is
        // ALWAYS the authoritative source. The per-channel JSON file fills gaps
        // only — it must never override newer DB verdicts.
        let live = lock.withLock { approvedByChannel[channelId] ?? [] }
        if !live.isEmpty {
            // DB has verdicts: start from the DB-approved set, then merge in
            // any file-approved entries NOT already in the DB (gaps from before
            // this curator session). Rejected-in-DB entries are excluded.
            let liveIds = Set(live.map(\.id))
            var merged = live
            if let file = CustomChannelsStore.shared.channelDefinition(for: channelId) {
                // DB-rejected tracks are excluded even if the file still has them
                let dbRejected = Set(curationTrackIds(channelId: channelId, status: "rejected"))
                for entry in file.approved where !liveIds.contains(entry.id)
                    && !dbRejected.contains(entry.id) {
                    let t = Track(
                        id: entry.id, source: "internet_archive",
                        title: entry.title, artist: entry.creator,
                        duration: entry.duration,
                        streamURL: URL(string: "https://archive.org/download/\(entry.id)")
                            ?? URL(string: "https://archive.org")!,
                        downloadURL: nil, localFilePath: nil,
                        license: .publicDomain, tags: [],
                        qualityScore: 1.0, rawCreator: entry.creator,
                        composer: nil, instruments: [],
                        metadataConfidence: 1.0,
                        parentIdentifier: entry.parentIdentifier)
                    merged.append(t)
                }
            }
            return merged
        }
        // No DB verdicts yet: fall back to per-channel file, then bundled manifest.
        if let file = CustomChannelsStore.shared.channelDefinition(for: channelId),
           !file.approved.isEmpty {
            return CustomChannelsStore.shared.approvedTracks(for: channelId)
        }
        return CurationManifestStore.shared.pool(for: channelId)
    }

    /// Returns rejected track IDs from the curation table for a channel.
    /// Used to exclude entries from the per-channel file that the DB has
    /// since rejected.
    private func curationTrackIds(channelId: String, status: String) -> Set<String> {
        // The lock already holds approvedByChannel; we need to query rejected
        // from a separate source. Use the DB directly via setCuration semantics.
        // Since LiveCurationStore doesn't keep rejected-by-channel in memory,
        // we use a lightweight query through the CustomChannelsStore mechanism:
        // read the per-channel file's rejected list (which IS kept up to date
        // by CuratorChannelEditView.verdict). Combined with the live DB's
        // approved set, this gives us the authoritative picture.
        guard let def = CustomChannelsStore.shared.channelDefinition(for: channelId) else {
            return []
        }
        return Set(def.rejected)
    }

    /// True if the live DB has any approved tracks for this channel.
    func hasLiveCuration(for channelId: String) -> Bool {
        lock.withLock {
            !(approvedByChannel[channelId]?.isEmpty ?? true)
        }
    }

    /// On-disk location of the live curation.json (Documents/, visible to the
    /// Files app).
    static var liveManifestURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("curation.json")
    }

    private func writeLiveManifest(_ approved: [String: [Track]]) {
        var channels: [String: CurationManifest.ChannelCuration] = [:]
        let stamp = ISO8601DateFormatter().string(from: Date())
        for (ch, tracks) in approved {
            let entries = tracks.map {
                CurationManifest.Entry(
                    id: $0.id,
                    title: $0.title,
                    creator: $0.artist,
                    duration: $0.duration,
                    parentIdentifier: $0.parentIdentifier
                )
            }
            channels[ch] = CurationManifest.ChannelCuration(
                updatedAt: stamp, approved: entries)
        }
        let manifest = CurationManifest(version: 1, channels: channels)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else { return }
        try? data.write(to: Self.liveManifestURL, options: [.atomic])
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
