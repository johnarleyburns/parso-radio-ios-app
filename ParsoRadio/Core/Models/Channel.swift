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
        Channel(
            id: "jazz-piano",
            name: "Jazz Piano",
            category: "Jazz & Blues",
            icon: "pianokeys",
            instruments: ["piano"],
            tags: ["jazz"]
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
        Channel(
            id: "old-time-roots",
            name: "Old-Time & Roots",
            category: "Rock & Country",
            icon: "banjo",
            tags: ["old-time", "folk"]
        ),

        // MARK: Vibes
        Channel(
            id: "soft-cafe",
            name: "Soft Café",
            category: "Vibes",
            icon: "cup.and.saucer",
            tags: ["jazz", "bossa nova"]
        ),
        Channel(
            id: "study-focus",
            name: "Study Focus",
            category: "Vibes",
            icon: "book",
            tags: ["instrumental", "ambient"]
        ),

        // MARK: Electronic & Beats
        Channel(
            id: "electronic",
            name: "Electronic",
            category: "Electronic & Beats",
            icon: "dot.radiowaves.left.and.right",
            tags: ["electronic"]
        ),
        Channel(
            id: "hip-hop",
            name: "Hip-Hop",
            category: "Electronic & Beats",
            icon: "mic.fill",
            tags: ["hip-hop"]
        ),
        Channel(
            id: "experimental",
            name: "Experimental",
            category: "Electronic & Beats",
            icon: "wand.and.stars",
            tags: ["experimental"]
        ),
        Channel(
            id: "instrumental",
            name: "Instrumental",
            category: "Electronic & Beats",
            icon: "tuningfork",
            tags: ["instrumental"]
        ),

        // MARK: Pop & World
        Channel(
            id: "pop",
            name: "Pop",
            category: "Pop & World",
            icon: "star.fill",
            tags: ["pop"]
        ),
        Channel(
            id: "world-music",
            name: "World Music",
            category: "Pop & World",
            icon: "globe",
            tags: ["world music"]
        ),

        // MARK: LibriVox Audiobooks (spoken word — position is persisted across sessions)
        Channel(
            id: "greek-philosophy",
            name: "Greek Philosophy",
            category: "LibriVox Audiobooks",
            icon: "building.columns",
            tags: ["plato", "socrates", "aristotle"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "childrens-books",
            name: "Children's Books",
            category: "LibriVox Audiobooks",
            icon: "star.circle",
            tags: ["children"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "science-fiction",
            name: "Science Fiction",
            category: "LibriVox Audiobooks",
            icon: "sparkles",
            tags: ["science fiction"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "mystery",
            name: "Mystery & Detection",
            category: "LibriVox Audiobooks",
            icon: "magnifyingglass",
            tags: ["mystery"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "classic-lit",
            name: "Classic Literature",
            category: "LibriVox Audiobooks",
            icon: "books.vertical",
            tags: ["classical fiction"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "history-talks",
            name: "History",
            category: "LibriVox Audiobooks",
            icon: "globe.europe.africa",
            tags: ["history"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),

        // MARK: World Classics — spoken word in various languages
        Channel(
            id: "chinese-philosophy",
            name: "Chinese Philosophy",
            category: "LibriVox Audiobooks",
            icon: "yin.yang",
            tags: ["confucius", "tao", "chinese philosophy"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "chinese-history",
            name: "Chinese History",
            category: "LibriVox Audiobooks",
            icon: "building.2",
            tags: ["china", "chinese history"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "greek-history",
            name: "Greek History",
            category: "LibriVox Audiobooks",
            icon: "building.columns.fill",
            tags: ["herodotus", "greek history", "ancient greece"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "french-lit",
            name: "French Literature",
            category: "LibriVox Audiobooks",
            icon: "books.vertical.fill",
            tags: ["french literature", "hugo", "dumas"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "spanish-lit",
            name: "Spanish Literature",
            category: "LibriVox Audiobooks",
            icon: "scroll",
            tags: ["spanish fiction", "cervantes"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "french-kids",
            name: "French Children's Books",
            category: "LibriVox Audiobooks",
            icon: "star.circle.fill",
            tags: ["children", "french"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),
        Channel(
            id: "spanish-kids",
            name: "Spanish Children's Books",
            category: "LibriVox Audiobooks",
            icon: "star.bubble",
            tags: ["children", "spanish"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"]
        ),

        Channel(
            id: "soul-rnb",
            name: "Soul & R&B",
            category: "Pop & World",
            icon: "heart.fill",
            tags: ["soul", "r&b"]
        ),

        // MARK: Pop & World — music
        Channel(
            id: "spanish-guitar",
            name: "Spanish Guitar & Flamenco",
            category: "Pop & World",
            icon: "guitars.fill",
            tags: ["flamenco", "spanish", "world music"]
        ),

        // MARK: FMA — Free Music Archive genre channels (all curl-verified: 40 PD+CC-BY tracks each)
        Channel(
            id: "fma-classical",
            name: "FMA Classical",
            category: "FMA",
            icon: "music.quarternote.3",
            tags: ["classical"]
        ),
        Channel(
            id: "fma-jazz",
            name: "FMA Jazz",
            category: "FMA",
            icon: "music.mic",
            tags: ["jazz"]
        ),
        Channel(
            id: "fma-blues",
            name: "FMA Blues",
            category: "FMA",
            icon: "guitars",
            tags: ["blues"]
        ),
        Channel(
            id: "fma-rock",
            name: "FMA Rock",
            category: "FMA",
            icon: "bolt.fill",
            tags: ["rock"]
        ),
        Channel(
            id: "fma-country",
            name: "FMA Country",
            category: "FMA",
            icon: "leaf",
            tags: ["country"]
        ),
        Channel(
            id: "fma-folk",
            name: "FMA Folk",
            category: "FMA",
            icon: "music.note",
            tags: ["folk"]
        ),
        Channel(
            id: "fma-instrumental",
            name: "FMA Instrumental",
            category: "FMA",
            icon: "tuningfork",
            tags: ["instrumental"]
        ),
        Channel(
            id: "fma-electronic",
            name: "FMA Electronic",
            category: "FMA",
            icon: "dot.radiowaves.left.and.right",
            tags: ["electronic"]
        ),
        Channel(
            id: "fma-hip-hop",
            name: "FMA Hip-Hop",
            category: "FMA",
            icon: "mic.fill",
            tags: ["hip-hop"]
        ),
        Channel(
            id: "fma-pop",
            name: "FMA Pop",
            category: "FMA",
            icon: "star.fill",
            tags: ["pop"]
        ),
        Channel(
            id: "fma-soul-rnb",
            name: "FMA Soul & R&B",
            category: "FMA",
            icon: "heart.fill",
            tags: ["soul"]
        ),
        Channel(
            id: "fma-experimental",
            name: "FMA Experimental",
            category: "FMA",
            icon: "wand.and.stars",
            tags: ["experimental"]
        ),
        Channel(
            id: "fma-international",
            name: "FMA International",
            category: "FMA",
            icon: "globe",
            tags: ["world music"]
        ),
        Channel(
            id: "fma-old-time",
            name: "FMA Old-Time & Historic",
            category: "FMA",
            icon: "banjo",
            tags: ["old-time"]
        ),
    ]

    // Ordered, deduplicated category names for section display.
    static var categories: [String] {
        var seen = Set<String>()
        return defaults.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}
