import Foundation

struct Channel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let icon: String          // SF Symbol name
    let composers: [String]
    let instruments: [String]
    let tags: [String]
    var isDownloaded: Bool

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
            tags: ["classical", "baroque"],
            isDownloaded: false
        ),
        Channel(
            id: "chopin-rachmaninoff-piano",
            name: "Chopin & Rachmaninoff — Piano",
            category: "Classical",
            icon: "pianokeys",
            composers: ["chopin", "rachmaninoff"],
            instruments: ["piano"],
            tags: ["classical", "romantic"],
            isDownloaded: false
        ),
        Channel(
            id: "classical",
            name: "Classical",
            category: "Classical",
            icon: "music.quarternote.3",
            composers: [],
            instruments: [],
            tags: ["classical"],
            isDownloaded: false
        ),
        Channel(
            id: "ambient",
            name: "Ambient",
            category: "Classical",
            icon: "waveform",
            composers: [],
            instruments: [],
            tags: ["ambient"],
            isDownloaded: false
        ),

        // MARK: Jazz & Blues
        Channel(
            id: "jazz-bar",
            name: "Jazz Bar",
            category: "Jazz & Blues",
            icon: "music.mic",
            composers: [],
            instruments: [],
            tags: ["jazz"],
            isDownloaded: false
        ),
        Channel(
            id: "blues",
            name: "Blues",
            category: "Jazz & Blues",
            icon: "guitars",
            composers: [],
            instruments: [],
            tags: ["blues"],
            isDownloaded: false
        ),

        // MARK: Rock & Country
        Channel(
            id: "rock",
            name: "Rock",
            category: "Rock & Country",
            icon: "bolt.fill",
            composers: [],
            instruments: [],
            tags: ["rock"],
            isDownloaded: false
        ),
        Channel(
            id: "country",
            name: "Country Road",
            category: "Rock & Country",
            icon: "leaf",
            composers: [],
            instruments: [],
            tags: ["country"],
            isDownloaded: false
        ),
        Channel(
            id: "folk",
            name: "Folk",
            category: "Rock & Country",
            icon: "music.note",
            composers: [],
            instruments: [],
            tags: ["folk"],
            isDownloaded: false
        ),

        // MARK: Vibes
        Channel(
            id: "soft-cafe",
            name: "Soft Café",
            category: "Vibes",
            icon: "cup.and.saucer",
            composers: [],
            instruments: [],
            tags: ["acoustic", "lo-fi"],
            isDownloaded: false
        ),
        Channel(
            id: "study-focus",
            name: "Study Focus",
            category: "Vibes",
            icon: "book",
            composers: [],
            instruments: [],
            tags: ["lo-fi", "ambient"],
            isDownloaded: false
        ),
    ]

    // Ordered, deduplicated category names for section display.
    static var categories: [String] {
        var seen = Set<String>()
        return defaults.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}
