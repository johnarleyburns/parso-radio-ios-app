import Foundation
import Combine

// MARK: - Per-channel JSON model

/// One file per channel in `Documents/curated-channels/<id>.json`.
/// The same shape for imported / shared files.
struct ChannelDefinition: Codable, Equatable {
    struct Info: Codable, Equatable {
        let id: String
        var name: String
        var icon: String
        var iaQuery: String?
    }
    struct ApprovedEntry: Codable, Equatable {
        let id: String
        let title: String
        let creator: String
        let duration: Double
        let parentIdentifier: String?
    }
    let version: Int
    var channel: Info
    var updatedAt: String
    var approved: [ApprovedEntry]
    var rejected: [String]
}

// MARK: - User metadata

struct CustomChannelsMeta: Codable {
    var customChannels: [ChannelMeta] = []
    var deletedDefaults: [String] = []
    var order: [String] = []
}

struct ChannelMeta: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var icon: String
    var iaQuery: String?
    let createdAt: String
    let isShippedDefault: Bool
}

// MARK: - CustomChannelsStore

/// Manages per-user, per-channel curated channels.
///
/// On launch:
/// 1. Reads each shipped default from the bundle (read-only).
/// 2. Reads each user override / addition from `Documents/curated-channels/`.
/// 3. Builds the runtime channel list from the union.
final class CustomChannelsStore: ObservableObject {
    static let shared = CustomChannelsStore()

    /// Directory for per-channel JSON files (both user-created and shipped-default overrides).
    static var channelsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("curated-channels")
    }

    static var metaURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("custom-channels-meta.json")
    }

    @Published private(set) var customChannels: [ChannelMeta] = []
    @Published private(set) var deletedDefaults: [String] = []
    @Published private(set) var channelOrder: [String] = []

    // MARK: - Init / Bootstrap

    private init() {
        ensureDirectory()
        loadMeta()
        loadBundledDefaults()
        migrateFromLiveManifest()
        applyOrder()
    }

    /// Called AFTER DatabaseService is ready (async). Pulls approved tracks
    /// from the SQLite DB for any channel whose per-channel file still has
    /// no approved entries (i.e. the user curated on a prior build and the
    /// tracks are in the DB but not yet in the per-channel JSON).
    func bootstrapFromDatabase(db: DatabaseService) async {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var merged = 0
        for chId in Channel.defaults
            .filter({ $0.category == "Curated" && $0.iaQueryEntry != nil })
            .map(\.id) {
            // Only backfill if the per-channel file exists but has no approved tracks
            guard var def = channelDefinition(for: chId),
                  def.approved.isEmpty else { continue }
            let approved = await db.fetchApprovedTracks(forChannelId: chId)
            guard !approved.isEmpty else { continue }
            def.approved = approved.map { t in
                ChannelDefinition.ApprovedEntry(
                    id: t.id, title: t.title, creator: t.artist,
                    duration: t.duration, parentIdentifier: t.parentIdentifier)
            }
            def.updatedAt = stamp
            writeChannelDefinition(def)
            merged += 1
        }
        if merged > 0 {
            Log.general.info("[CustomChannels] Backfilled \(merged) channels from SQLite DB")
        }
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: Self.channelsDir,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Migration (Phase A)

    /// Read the LIVE `Documents/curation.json` (written by LiveCurationStore
    /// on prior launches) and merge any approved tracks into per-channel files.
    /// Only runs when per-channel files exist but have no approved tracks yet.
    private func migrateFromLiveManifest() {
        // 1. Try the live Documents/curation.json first (has the user's hours of work)
        let docsURL = LiveCurationStore.liveManifestURL
        let liveManifest: CurationManifest?
        if let data = try? Data(contentsOf: docsURL),
           let m = try? JSONDecoder().decode(CurationManifest.self, from: data) {
            liveManifest = m
        } else {
            liveManifest = nil
        }

        // 2. For each curated channel that already has a per-channel file
        //    (copied from bundle by loadBundledDefaults), merge in approved
        //    tracks from the live manifest.
        let shippedChannels = Channel.defaults
            .filter { $0.category == "Curated" && $0.iaQueryEntry != nil }
            .map(\.id)
        let stamp = ISO8601DateFormatter().string(from: Date())

        for chId in shippedChannels {
            let dest = Self.channelsDir.appendingPathComponent("\(chId).json")
            guard FileManager.default.fileExists(atPath: dest.path) else { continue }

            // Read the current per-channel file (already has metadata from bundle)
            guard var def = channelDefinition(for: chId) else { continue }

            // If it already has approved tracks (from a prior migration or curation),
            // skip — never overwrite the user's existing per-channel file.
            guard def.approved.isEmpty else { continue }

            // Merge approved tracks from the live manifest
            if let live = liveManifest {
                let entries = live.approved(for: chId)
                if !entries.isEmpty {
                    def.approved = entries.map { entry in
                        ChannelDefinition.ApprovedEntry(
                            id: entry.id, title: entry.title,
                            creator: entry.creator,
                            duration: entry.duration,
                            parentIdentifier: entry.parentIdentifier)
                    }
                    def.updatedAt = stamp
                    writeChannelDefinition(def)
                }
            }
        }
    }

    // MARK: - Shipped defaults

    /// For every shipped channel that has a bundled per-channel file,
    /// ensure it exists in the user's Documents with current metadata
    /// (name, icon, iaQuery). If a per-channel file already exists from
    /// prior curation, the migration step re-merges approved tracks so
    /// no curation work is lost.
    private func loadBundledDefaults() {
        let shippedIds = Channel.defaults
            .filter { $0.category == "Curated" && $0.iaQueryEntry != nil }
            .map(\.id)

        let stamp = ISO8601DateFormatter().string(from: Date())
        let fm = FileManager.default
        var foundInBundle = 0
        var copiedToDocs = 0

        for chId in shippedIds {
            // XcodeGen flattens directory groups into the bundle root,
            // so each per-channel JSON sits at e.g. "chamber-music.json".
            guard let bundleURL = Bundle.main.url(
                forResource: chId, withExtension: "json") else {
                continue
            }
            foundInBundle += 1

            let userFile = Self.channelsDir.appendingPathComponent("\(chId).json")
            try? fm.removeItem(at: userFile)
            do {
                try fm.copyItem(at: bundleURL, to: userFile)
                copiedToDocs += 1
            } catch { /* skip */ }

            if !customChannels.contains(where: { $0.id == chId }) {
                let channel = Channel.defaults.first(where: { $0.id == chId })
                let meta = ChannelMeta(
                    id: chId,
                    name: channel?.name ?? chId,
                    icon: channel?.icon ?? "star",
                    iaQuery: IAQueryRegistry.shared.entry(for: chId)?.iaQuery,
                    createdAt: stamp,
                    isShippedDefault: true)
                customChannels.append(meta)
                if !channelOrder.contains(chId) {
                    channelOrder.append(chId)
                }
            }
        }
        saveMeta()
        Log.general.info("[CustomChannels] Bundle: found \(foundInBundle)/\(shippedIds.count), copied \(copiedToDocs) to Documents")
    }

    // MARK: - Meta persistence

    private func loadMeta() {
        guard let data = try? Data(contentsOf: Self.metaURL),
              let meta = try? JSONDecoder().decode(CustomChannelsMeta.self, from: data)
        else { return }
        customChannels = meta.customChannels
        deletedDefaults = meta.deletedDefaults
        channelOrder = meta.order
    }

    private func saveMeta() {
        let meta = CustomChannelsMeta(
            customChannels: customChannels,
            deletedDefaults: deletedDefaults,
            order: channelOrder)
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: Self.metaURL, options: .atomic)
    }

    // MARK: - Channel definition I/O

    func channelDefinition(for chId: String) -> ChannelDefinition? {
        let url = Self.channelsDir.appendingPathComponent("\(chId).json")
        guard let data = try? Data(contentsOf: url),
              let def = try? JSONDecoder().decode(ChannelDefinition.self, from: data)
        else { return nil }
        return def
    }

    func writeChannelDefinition(_ def: ChannelDefinition) {
        let url = Self.channelsDir.appendingPathComponent("\(def.channel.id).json")
        var updated = def
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(updated) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Channel lifecycle

    /// Ordered list of visible channels (shipped defaults not deleted + user custom),
    /// sorted alphabetically by name unless the user has manually reordered.
    func orderedChannels() -> [ChannelMeta] {
        let list: [ChannelMeta] = channelOrder.compactMap { id in
            guard !deletedDefaults.contains(id) else { return nil }
            return customChannels.first(where: { $0.id == id })
        }
        return list
    }

    /// Populate channelOrder alphabetically on first launch (no saved order).
    fileprivate func applyOrder() {
        guard channelOrder.isEmpty else { return }
        let shipped = customChannels
            .filter { $0.isShippedDefault }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        channelOrder = shipped.map(\.id)
        // Append any custom (non-shipped) channels after the alphabetized defaults
        for meta in customChannels where !meta.isShippedDefault {
            if !channelOrder.contains(meta.id) {
                channelOrder.append(meta.id)
            }
        }
        saveMeta()
    }

    func addChannel(name: String, icon: String, iaQuery: String?, initialTracks: [Track] = []) -> String {
        let chId = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let meta = ChannelMeta(
            id: chId, name: name, icon: icon, iaQuery: iaQuery,
            createdAt: stamp, isShippedDefault: false)
        customChannels.append(meta)
        channelOrder.append(chId)

        let approvedEntries = initialTracks.map {
            ChannelDefinition.ApprovedEntry(
                id: $0.id, title: $0.title, creator: $0.artist,
                duration: $0.duration, parentIdentifier: $0.parentIdentifier)
        }
        let def = ChannelDefinition(
            version: 1,
            channel: ChannelDefinition.Info(id: chId, name: name, icon: icon, iaQuery: iaQuery),
            updatedAt: stamp,
            approved: approvedEntries,
            rejected: [])
        writeChannelDefinition(def)
        saveMeta()
        return chId
    }

    func renameChannel(chId: String, newName: String) {
        guard var def = channelDefinition(for: chId) else { return }
        def.channel = ChannelDefinition.Info(
            id: def.channel.id, name: newName, icon: def.channel.icon,
            iaQuery: def.channel.iaQuery)
        writeChannelDefinition(def)

        if let idx = customChannels.firstIndex(where: { $0.id == chId }) {
            customChannels[idx].name = newName
        }
        saveMeta()
    }

    func updateIcon(chId: String, newIcon: String) {
        guard var def = channelDefinition(for: chId) else { return }
        def.channel = ChannelDefinition.Info(
            id: def.channel.id, name: def.channel.name, icon: newIcon,
            iaQuery: def.channel.iaQuery)
        writeChannelDefinition(def)

        if let idx = customChannels.firstIndex(where: { $0.id == chId }) {
            customChannels[idx].icon = newIcon
        }
        saveMeta()
    }

    func updateQuery(chId: String, newQuery: String?) {
        guard var def = channelDefinition(for: chId) else { return }
        def.channel = ChannelDefinition.Info(
            id: def.channel.id, name: def.channel.name, icon: def.channel.icon,
            iaQuery: newQuery)
        writeChannelDefinition(def)

        if let idx = customChannels.firstIndex(where: { $0.id == chId }) {
            customChannels[idx].iaQuery = newQuery
        }
        saveMeta()
    }

    func duplicateChannel(chId: String) -> String? {
        guard let def = channelDefinition(for: chId) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let newId = "\(chId)-copy"
        let meta = ChannelMeta(
            id: newId,
            name: "\(def.channel.name) Copy",
            icon: def.channel.icon,
            iaQuery: def.channel.iaQuery,
            createdAt: stamp,
            isShippedDefault: false)
        customChannels.append(meta)
        if let idx = channelOrder.firstIndex(of: chId) {
            channelOrder.insert(newId, at: idx + 1)
        } else {
            channelOrder.append(newId)
        }

        var copy = def
        copy.channel = ChannelDefinition.Info(
            id: newId, name: meta.name, icon: meta.icon, iaQuery: meta.iaQuery)
        copy.approved = []   // fresh review queue for the copy
        copy.rejected = []
        writeChannelDefinition(copy)
        saveMeta()
        return newId
    }

    func deleteChannel(chId: String) {
        if customChannels.first(where: { $0.id == chId && $0.isShippedDefault }) != nil {
            // Shipped default: record in deletedDefaults (don't delete file).
            if !deletedDefaults.contains(chId) {
                deletedDefaults.append(chId)
            }
        } else {
            // Custom channel: remove the file.
            let url = Self.channelsDir.appendingPathComponent("\(chId).json")
            try? FileManager.default.removeItem(at: url)
            customChannels.removeAll(where: { $0.id == chId })
        }
        channelOrder.removeAll(where: { $0 == chId })
        saveMeta()
    }

    func reorder(channels: [ChannelMeta]) {
        channelOrder = channels.map(\.id)
        saveMeta()
    }

    func restoreDefaults() {
        deletedDefaults.removeAll()
        saveMeta()
    }

    // MARK: - Approved pool (for QueueManager)

    /// Approved tracks for a channel from its per-channel file.
    func approvedTracks(for chId: String) -> [Track] {
        guard let def = channelDefinition(for: chId) else { return [] }
        return def.approved.map { entry in
            Track(
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
        }
    }

    /// ChannelMeta → a lightweight runtime Channel for playback.
    func runtimeChannel(from meta: ChannelMeta) -> Channel {
        Channel(
            id: meta.id, name: meta.name, category: "Curated", icon: meta.icon,
            contentType: .music, preferredSource: "internet_archive",
            isDownloaded: false)
    }

    /// Approved tracks known for this channel (from per-channel file).
    func hasApprovedTracks(for chId: String) -> Bool {
        !(channelDefinition(for: chId)?.approved.isEmpty ?? true)
    }

    // MARK: - Import / Export

    /// Export a channel definition file URL for sharing.
    func exportURL(for chId: String) -> URL {
        Self.channelsDir.appendingPathComponent("\(chId).json")
    }

    /// Import a channel from an external JSON file.
    /// Returns the channel ID on success, or throws on failure.
    func importChannel(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let def = try JSONDecoder().decode(ChannelDefinition.self, from: data)

        let destURL = Self.channelsDir.appendingPathComponent("\(def.channel.id).json")
        let exists = FileManager.default.fileExists(atPath: destURL.path)

        let finalId: String
        if exists {
            // Duplicate with a new ID
            finalId = "\(def.channel.id)-imported-\(Int(Date().timeIntervalSince1970))"
        } else {
            finalId = def.channel.id
        }

        var imported = def
        imported.channel = ChannelDefinition.Info(
            id: finalId, name: def.channel.name, icon: def.channel.icon,
            iaQuery: def.channel.iaQuery)
        writeChannelDefinition(imported)

        let stamp = ISO8601DateFormatter().string(from: Date())
        let meta = ChannelMeta(
            id: finalId, name: def.channel.name, icon: def.channel.icon,
            iaQuery: def.channel.iaQuery,
            createdAt: stamp, isShippedDefault: false)
        if !customChannels.contains(where: { $0.id == finalId }) {
            customChannels.append(meta)
        }
        if !channelOrder.contains(finalId) {
            channelOrder.append(finalId)
        }
        saveMeta()
        return finalId
    }
}
