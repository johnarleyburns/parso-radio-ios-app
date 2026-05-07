import Foundation

enum ContentType: String, Codable {
    case music
    case spokenWord
}

struct Channel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let icon: String          // SF Symbol name
    let composers: [String]
    let instruments: [String]
    let tags: [String]
    let contentType: ContentType
    // IA collection names to restrict spoken-word searches (empty = general search).
    let spokenWordCollections: [String]
    var isDownloaded: Bool

    init(
        id: String, name: String, category: String, icon: String,
        composers: [String] = [], instruments: [String] = [], tags: [String] = [],
        contentType: ContentType = .music, spokenWordCollections: [String] = [],
        isDownloaded: Bool = false
    ) {
        self.id = id; self.name = name; self.category = category; self.icon = icon
        self.composers = composers; self.instruments = instruments; self.tags = tags
        self.contentType = contentType; self.spokenWordCollections = spokenWordCollections
        self.isDownloaded = isDownloaded
    }

    func matches(_ track: Track) -> Bool {
        // Tag-only channels (no composer/instrument constraints) must match by tag —
        // otherwise every track in the DB satisfies the empty-array conditions and
        // e.g. Country Road ends up playing Rachmaninoff.
        if composers.isEmpty && instruments.isEmpty {
            return tags.isEmpty || tags.contains(where: { track.tags.contains($0) })
        }
        let composerMatch = composers.isEmpty || composers.contains(track.composer ?? "")
        let instrumentMatch = instruments.isEmpty
            || instruments.contains(where: { track.instruments.contains($0) })
        return composerMatch && instrumentMatch
    }
}

extension Channel {
    static let defaults: [Channel] = [
        // MARK: Classical
        Channel(
            id: "bach-vivaldi-strings",
            name: "Bach & Vivaldi — Strings",
            category: "Classical",
            icon: "music.note.list",
            composers: ["bach", "vivaldi"],
            instruments: ["strings"],
            tags: ["classical", "baroque"]
        ),
        Channel(
            id: "chopin-rachmaninoff-piano",
            name: "Chopin & Rachmaninoff — Piano",
            category: "Classical",
            icon: "pianokeys",
            composers: ["chopin", "rachmaninoff"],
            instruments: ["piano"],
            tags: ["classical", "romantic"]
        ),
        Channel(
            id: "classical",
            name: "Classical",
            category: "Classical",
            icon: "music.quarternote.3",
            tags: ["classical"]
        ),
        Channel(
            id: "ambient",
            name: "Ambient",
            category: "Classical",
            icon: "waveform",
            tags: ["ambient"]
        ),

        // MARK: Jazz & Blues
        Channel(
            id: "jazz-bar",
            name: "Jazz Bar",
            category: "Jazz & Blues",
            icon: "music.mic",
            tags: ["jazz"]
        ),
        Channel(
            id: "blues",
            name: "Blues",
            category: "Jazz & Blues",
            icon: "guitars",
            tags: ["blues"]
        ),

        // MARK: Rock & Country
        Channel(
            id: "rock",
            name: "Rock",
            category: "Rock & Country",
            icon: "bolt.fill",
            tags: ["rock"]
        ),
        Channel(
            id: "country",
            name: "Country Road",
            category: "Rock & Country",
            icon: "leaf",
            tags: ["country"]
        ),
        Channel(
            id: "folk",
            name: "Folk",
            category: "Rock & Country",
            icon: "music.note",
            tags: ["folk"]
        ),

        // MARK: Vibes
        Channel(
            id: "soft-cafe",
            name: "Soft Café",
            category: "Vibes",
            icon: "cup.and.saucer",
            tags: ["acoustic", "lo-fi"]
        ),
        Channel(
            id: "study-focus",
            name: "Study Focus",
            category: "Vibes",
            icon: "book",
            tags: ["lo-fi", "ambient"]
        ),

        // MARK: Talk & Stories (spoken word — position is persisted across sessions)
        Channel(
            id: "greek-philosophy",
            name: "Greek Philosophy",
            category: "Talk & Stories",
            icon: "building.columns",
            tags: ["plato", "socrates", "aristotle"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "childrens-books",
            name: "Children's Books",
            category: "Talk & Stories",
            icon: "star.circle",
            tags: ["children"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "science-fiction",
            name: "Science Fiction",
            category: "Talk & Stories",
            icon: "sparkles",
            tags: ["science fiction"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "mystery",
            name: "Mystery & Detection",
            category: "Talk & Stories",
            icon: "magnifyingglass",
            tags: ["mystery"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "classic-lit",
            name: "Classic Literature",
            category: "Talk & Stories",
            icon: "books.vertical",
            tags: ["classical fiction"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "history-talks",
            name: "History",
            category: "Talk & Stories",
            icon: "globe.europe.africa",
            tags: ["history"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
    ]

    // Ordered, deduplicated category names for section display.
    static var categories: [String] {
        var seen = Set<String>()
        return defaults.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}
