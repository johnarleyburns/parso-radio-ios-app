import AppIntents

struct ChannelEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Channel")
    static let defaultQuery = ChannelEntityQuery()

    let id: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

struct ChannelEntityQuery: EntityQuery {
    func entities(for identifiers: [ChannelEntity.ID]) async throws -> [ChannelEntity] {
        Channel.defaults
            .filter { identifiers.contains($0.id) }
            .map { ChannelEntity(id: $0.id, displayName: $0.name) }
    }

    func suggestedEntities() async throws -> [ChannelEntity] {
        let visited = UserDefaults.standard.stringArray(forKey: "visitedChannelIds") ?? []
        let ordered = visited.compactMap { id in
            Channel.defaults.first { $0.id == id }
        } + Channel.defaults.filter { !visited.contains($0.id) }
        return Array(ordered.prefix(40)).map {
            ChannelEntity(id: $0.id, displayName: $0.name)
        }
    }
}

struct PodcastEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Podcast")
    static let defaultQuery = PodcastEntityQuery()

    let id: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

struct PodcastEntityQuery: EntityQuery {
    func entities(for identifiers: [PodcastEntity.ID]) async throws -> [PodcastEntity] {
        Channel.defaults
            .filter { $0.category == "Podcasts" && identifiers.contains($0.id) }
            .map { PodcastEntity(id: $0.id, displayName: $0.name) }
    }

    func suggestedEntities() async throws -> [PodcastEntity] {
        Channel.defaults
            .filter { $0.category == "Podcasts" }
            .map { PodcastEntity(id: $0.id, displayName: $0.name) }
    }
}
