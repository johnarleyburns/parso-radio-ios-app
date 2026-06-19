import Foundation
import SwiftUI

struct IACollection: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let curator: String
    let icon: String
    var isDefault: Bool = false

    var channelId: String { "ia-collection-\(id)" }
    var iaQuery: String { "collection:\(id)" }
    var archiveURL: URL? { URL(string: "https://archive.org/details/\(id)") }

    func asChannel() -> Channel {
        Channel(
            id: channelId,
            name: title,
            category: "Curated Music",
            icon: icon,
            tags: [channelId],
            preferredSource: "internet_archive",
            iaQuery: iaQuery
        )
    }
}

@MainActor
final class IACollectionStore: ObservableObject {
    static let shared = IACollectionStore()

    @Published private(set) var collections: [IACollection] = []

    private let userCollectionsKey = "iaCollectionStore.userCollections"
    private let removedDefaultsKey = "iaCollectionStore.removedDefaults"

    private init() {
        loadCollections()
    }

    var channels: [Channel] {
        collections.map { $0.asChannel() }
    }

    func addCollection(_ collection: IACollection) {
        guard !collections.contains(where: { $0.id == collection.id }) else { return }
        var c = collection
        c.isDefault = false
        var userCollections = loadUserCollections()
        userCollections.append(c)
        saveUserCollections(userCollections)
        var removed = loadRemovedDefaults()
        removed.remove(c.id)
        saveRemovedDefaults(removed)
        loadCollections()
    }

    func addCollection(id: String, title: String) {
        let c = IACollection(
            id: id, title: title, category: "user",
            curator: "", icon: "music.note", isDefault: false
        )
        addCollection(c)
    }

    func removeCollection(_ collection: IACollection) {
        if collection.isDefault {
            var removed = loadRemovedDefaults()
            removed.insert(collection.id)
            saveRemovedDefaults(removed)
        } else {
            var userCollections = loadUserCollections()
            userCollections.removeAll { $0.id == collection.id }
            saveUserCollections(userCollections)
        }
        loadCollections()
    }

    func collection(forChannelId channelId: String) -> IACollection? {
        collections.first { $0.channelId == channelId }
    }

    private func loadCollections() {
        let defaults = loadDefaultCollections()
        let removed = loadRemovedDefaults()
        let user = loadUserCollections()
        var result = defaults.filter { !removed.contains($0.id) }
        let existingIds = Set(result.map(\.id))
        for c in user where !existingIds.contains(c.id) {
            result.append(c)
        }
        collections = result
    }

    private func loadDefaultCollections() -> [IACollection] {
        guard let url = Bundle.main.url(forResource: "default_collections", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              var list = try? JSONDecoder().decode([IACollection].self, from: data)
        else { return [] }
        for i in list.indices { list[i].isDefault = true }
        return list
    }

    private func loadUserCollections() -> [IACollection] {
        guard let data = UserDefaults.standard.data(forKey: userCollectionsKey),
              let list = try? JSONDecoder().decode([IACollection].self, from: data)
        else { return [] }
        return list
    }

    private func saveUserCollections(_ collections: [IACollection]) {
        if let data = try? JSONEncoder().encode(collections) {
            UserDefaults.standard.set(data, forKey: userCollectionsKey)
        }
    }

    private func loadRemovedDefaults() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: removedDefaultsKey) ?? [])
    }

    private func saveRemovedDefaults(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: removedDefaultsKey)
    }
}
