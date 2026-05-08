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
    // UC18: if set, DatabaseService.fetchTracks filters to this source string only.
    let preferredSource: String?
    var isDownloaded: Bool

    init(
        id: String, name: String, category: String, icon: String,
        composers: [String] = [], instruments: [String] = [], tags: [String] = [],
        contentType: ContentType = .music, spokenWordCollections: [String] = [],
        preferredSource: String? = nil, isDownloaded: Bool = false
    ) {
        self.id = id; self.name = name; self.category = category; self.icon = icon
        self.composers = composers; self.instruments = instruments; self.tags = tags
        self.contentType = contentType; self.spokenWordCollections = spokenWordCollections
        self.preferredSource = preferredSource; self.isDownloaded = isDownloaded
    }

    func matches(_ track: Track) -> Bool {
        // Tag-only channels (no composer/instrument constraints) must match by tag —
        // otherwise every track in the DB satisfies the empty-array conditions and
        // e.g. a Country channel ends up playing Rachmaninoff.
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

        // MARK: Classical — Format/Period channels (UC16)
        // subject: queries; curl-verified against archive.org Solr before adding.
        Channel(
            id: "baroque", name: "Baroque", category: "Classical",
            icon: "music.quarternote.3", tags: ["baroque"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "romantic-era", name: "Romantic Era", category: "Classical",
            icon: "pianokeys", tags: ["romantic"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "early-music", name: "Early Music", category: "Classical",
            icon: "music.note", tags: ["early music", "renaissance"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "symphony", name: "Symphony & Orchestra", category: "Classical",
            icon: "music.note.list", tags: ["symphony"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "opera", name: "Opera", category: "Classical",
            icon: "theatermasks", tags: ["opera"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "chamber-music", name: "Chamber Music", category: "Classical",
            icon: "guitars", tags: ["chamber music", "string quartet"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "piano-classics", name: "Piano Classics", category: "Classical",
            icon: "pianokeys", tags: ["piano", "classical"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "organ-harpsichord", name: "Organ & Harpsichord", category: "Classical",
            icon: "waveform", tags: ["organ", "harpsichord"],
            preferredSource: "internet_archive"
        ),

        // MARK: Classical — Individual composer channels (UC16)
        // creator: queries; curl-verified. ComposerMap normalizes aliases.
        Channel(
            id: "bach", name: "Bach", category: "Classical",
            icon: "music.note", composers: ["bach"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "mozart", name: "Mozart", category: "Classical",
            icon: "music.note", composers: ["mozart"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "beethoven", name: "Beethoven", category: "Classical",
            icon: "music.note", composers: ["beethoven"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "schubert", name: "Schubert", category: "Classical",
            icon: "music.note", composers: ["schubert"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "schumann", name: "Schumann", category: "Classical",
            icon: "music.note", composers: ["schumann"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "brahms", name: "Brahms", category: "Classical",
            icon: "music.note", composers: ["brahms"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "haydn", name: "Haydn", category: "Classical",
            icon: "music.note", composers: ["haydn"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "chopin", name: "Chopin", category: "Classical",
            icon: "pianokeys", composers: ["chopin"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "rachmaninoff", name: "Rachmaninoff", category: "Classical",
            icon: "pianokeys", composers: ["rachmaninoff"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "vivaldi", name: "Vivaldi", category: "Classical",
            icon: "music.note", composers: ["vivaldi"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "handel", name: "Handel", category: "Classical",
            icon: "music.quarternote.3", composers: ["handel"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "telemann", name: "Telemann", category: "Classical",
            icon: "music.quarternote.3", composers: ["telemann"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "liszt", name: "Liszt", category: "Classical",
            icon: "pianokeys", composers: ["liszt"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "mendelssohn", name: "Mendelssohn", category: "Classical",
            icon: "music.note", composers: ["mendelssohn"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "tchaikovsky", name: "Tchaikovsky", category: "Classical",
            icon: "music.note.list", composers: ["tchaikovsky"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "dvorak", name: "Dvořák", category: "Classical",
            icon: "music.note", composers: ["dvorak"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "debussy", name: "Debussy", category: "Classical",
            icon: "waveform", composers: ["debussy"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "grieg", name: "Grieg", category: "Classical",
            icon: "music.note", composers: ["grieg"],
            preferredSource: "internet_archive"
        ),

        // MARK: LibriVox Audiobooks (spoken word — position is persisted across sessions)
        // Named channels use specific-name tags; genre channels use IA subject strings (curl-verified).
        Channel(
            id: "greek-philosophy",
            name: "Greek Philosophy",
            category: "LibriVox Audiobooks",
            icon: "building.columns",
            tags: ["plato", "socrates", "aristotle"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "chinese-philosophy",
            name: "Chinese Philosophy",
            category: "LibriVox Audiobooks",
            icon: "circle.lefthalf.filled",
            tags: ["confucius", "tao", "chinese philosophy"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "chinese-history",
            name: "Chinese History",
            category: "LibriVox Audiobooks",
            icon: "building.2",
            tags: ["china", "chinese history"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "greek-history",
            name: "Greek History",
            category: "LibriVox Audiobooks",
            icon: "building.columns.fill",
            tags: ["herodotus", "greek history", "ancient greece"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-poetry", name: "Poetry", category: "LibriVox Audiobooks",
            icon: "text.quote",
            tags: ["poetry"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-short-stories", name: "Short Stories", category: "LibriVox Audiobooks",
            icon: "books.vertical",
            tags: ["short stories"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-nature", name: "Nature", category: "LibriVox Audiobooks",
            icon: "leaf.fill",
            tags: ["nature"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-humor", name: "Humor & Satire", category: "LibriVox Audiobooks",
            icon: "face.smiling",
            tags: ["humor"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-science-fiction", name: "Science Fiction", category: "LibriVox Audiobooks",
            icon: "sparkles",
            tags: ["science fiction"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-travel", name: "Travel & Adventure", category: "LibriVox Audiobooks",
            icon: "map.fill",
            tags: ["travel"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-biography", name: "Biography", category: "LibriVox Audiobooks",
            icon: "person.text.rectangle.fill",
            tags: ["biography"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-drama", name: "Drama & Theater", category: "LibriVox Audiobooks",
            icon: "theatermasks.fill",
            tags: ["drama"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-philosophy", name: "Philosophy", category: "LibriVox Audiobooks",
            icon: "lightbulb.fill",
            tags: ["philosophy"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-religion", name: "Religion & Spirituality", category: "LibriVox Audiobooks",
            icon: "rays",
            tags: ["religion"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-science", name: "Science & Technology", category: "LibriVox Audiobooks",
            icon: "atom",
            tags: ["science"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-essays", name: "Essays & Speeches", category: "LibriVox Audiobooks",
            icon: "doc.text.fill",
            tags: ["essays"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-historical-fiction", name: "Historical Fiction", category: "LibriVox Audiobooks",
            icon: "clock.arrow.circlepath",
            tags: ["historical fiction"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-fairy-tales", name: "Fairy Tales", category: "LibriVox Audiobooks",
            icon: "wand.and.stars",
            tags: ["fairy tales"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-art", name: "Art & Music", category: "LibriVox Audiobooks",
            icon: "paintbrush.fill",
            tags: ["art"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-ghost-stories", name: "Ghost Stories", category: "LibriVox Audiobooks",
            icon: "moon.stars.fill",
            tags: ["ghost stories"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-folklore", name: "Folklore & Legends", category: "LibriVox Audiobooks",
            icon: "globe.europe.africa",
            tags: ["folklore"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-mythology", name: "Mythology", category: "LibriVox Audiobooks",
            icon: "building.columns",
            tags: ["mythology"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),

        // MARK: FMA — Free Music Archive genre channels (all curl-verified: 40 PD+CC-BY tracks each)
        Channel(
            id: "fma-classical", name: "FMA Classical", category: "FMA",
            icon: "music.quarternote.3", tags: ["classical"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-jazz", name: "FMA Jazz", category: "FMA",
            icon: "music.mic", tags: ["jazz"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-blues", name: "FMA Blues", category: "FMA",
            icon: "guitars", tags: ["blues"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-rock", name: "FMA Rock", category: "FMA",
            icon: "bolt.fill", tags: ["rock"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-country", name: "FMA Country", category: "FMA",
            icon: "leaf", tags: ["country"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-folk", name: "FMA Folk", category: "FMA",
            icon: "music.note", tags: ["folk"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-instrumental", name: "FMA Instrumental", category: "FMA",
            icon: "tuningfork", tags: ["instrumental"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-electronic", name: "FMA Electronic", category: "FMA",
            icon: "dot.radiowaves.left.and.right", tags: ["electronic"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-hip-hop", name: "FMA Hip-Hop", category: "FMA",
            icon: "mic.fill", tags: ["hip-hop"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-pop", name: "FMA Pop", category: "FMA",
            icon: "star.fill", tags: ["pop"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-soul-rnb", name: "FMA Soul & R&B", category: "FMA",
            icon: "heart.fill", tags: ["soul"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-experimental", name: "FMA Experimental", category: "FMA",
            icon: "wand.and.stars", tags: ["experimental"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-international", name: "FMA International", category: "FMA",
            icon: "globe", tags: ["world music"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-old-time", name: "FMA Old-Time & Historic", category: "FMA",
            icon: "guitars", tags: ["old-time"],
            preferredSource: "fma"
        ),

        // MARK: Oxford Lectures — University of Oxford open-license audio lectures
        // Each channel's tags contain the podcasts.ox.ac.uk unit slug used for track matching.
        // contentType: .spokenWord enables position-persist, 15 s rewind, next-track forward.
        Channel(
            id: "oxford-philosophy", name: "Philosophy", category: "Oxford Lectures",
            icon: "quote.bubble", tags: ["faculty-philosophy"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-history", name: "History", category: "Oxford Lectures",
            icon: "scroll", tags: ["faculty-history"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-english", name: "English Literature", category: "Oxford Lectures",
            icon: "books.vertical",
            tags: ["faculty-english-language-and-literature"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-torch", name: "TORCH — Humanities Research",
            category: "Oxford Lectures", icon: "lightbulb",
            tags: ["oxford-research-centre-humanities-torch"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-classics", name: "Classics", category: "Oxford Lectures",
            icon: "building.columns.fill", tags: ["faculty-classics"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-music", name: "Music", category: "Oxford Lectures",
            icon: "music.note.list", tags: ["faculty-music"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-physics", name: "Physics", category: "Oxford Lectures",
            icon: "atom", tags: ["department-physics"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-computer-science", name: "Computer Science",
            category: "Oxford Lectures", icon: "laptopcomputer",
            tags: ["department-computer-science"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-maths", name: "Mathematics", category: "Oxford Lectures",
            icon: "function", tags: ["mathematical-institute"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-engineering", name: "Engineering Science",
            category: "Oxford Lectures", icon: "gear",
            tags: ["department-engineering-science"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-chemistry", name: "Chemistry", category: "Oxford Lectures",
            icon: "drop.fill", tags: ["department-chemistry"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-business", name: "Saïd Business School",
            category: "Oxford Lectures", icon: "briefcase",
            tags: ["said-business-school"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-martin", name: "Oxford Martin School",
            category: "Oxford Lectures", icon: "globe",
            tags: ["oxford-martin-school"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-education", name: "Education", category: "Oxford Lectures",
            icon: "graduationcap", tags: ["department-education"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-internet", name: "Internet Institute (OII)",
            category: "Oxford Lectures", icon: "network",
            tags: ["oxford-internet-institute"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-blavatnik", name: "Blavatnik School of Government",
            category: "Oxford Lectures", icon: "building.2.fill",
            tags: ["blavatnik-school-government"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-economics", name: "Economics", category: "Oxford Lectures",
            icon: "chart.bar.fill", tags: ["department-economics"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-clinical-medicine", name: "Clinical Medicine (NDM)",
            category: "Oxford Lectures", icon: "stethoscope",
            tags: ["nuffield-department-clinical-medicine"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-population-health", name: "Population Health",
            category: "Oxford Lectures", icon: "heart.fill",
            tags: ["nuffield-department-population-health"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-surgical", name: "Surgical Sciences",
            category: "Oxford Lectures", icon: "cross.fill",
            tags: ["nuffield-department-surgical-sciences"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-psychology", name: "Psychology", category: "Oxford Lectures",
            icon: "brain.head.profile",
            tags: ["department-experimental-psychology"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-anatomy", name: "Physiology, Anatomy & Genetics",
            category: "Oxford Lectures", icon: "figure.stand",
            tags: ["department-physiology-anatomy-and-genetics-dpag"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
    ]

    // Ordered, deduplicated category names for section display.
    static var categories: [String] {
        var seen = Set<String>()
        return defaults.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}
