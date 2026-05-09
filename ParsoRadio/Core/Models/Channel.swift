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
    // News/podcast channels: RSS feed URL; nil for IA/FMA channels.
    let feedURL: String?
    var isDownloaded: Bool

    init(
        id: String, name: String, category: String, icon: String,
        composers: [String] = [], instruments: [String] = [], tags: [String] = [],
        contentType: ContentType = .music, spokenWordCollections: [String] = [],
        preferredSource: String? = nil, feedURL: String? = nil, isDownloaded: Bool = false
    ) {
        self.id = id; self.name = name; self.category = category; self.icon = icon
        self.composers = composers; self.instruments = instruments; self.tags = tags
        self.contentType = contentType; self.spokenWordCollections = spokenWordCollections
        self.preferredSource = preferredSource; self.feedURL = feedURL
        self.isDownloaded = isDownloaded
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
        // Curl-verified: "classical guitar" subject returns 259 items on IA; ~45% with CC/PD license.
        Channel(
            id: "classical-guitar", name: "Classical Guitar", category: "Classical",
            icon: "guitars", tags: ["classical guitar"],
            preferredSource: "internet_archive"
        ),
        // Curl-verified: "cello" subject returns 1,631 items on IA; broad but well-populated.
        Channel(
            id: "cello", name: "Cello", category: "Classical",
            icon: "music.note", tags: ["cello"],
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

        // MARK: Audiobooks (spoken word — position is persisted across sessions)
        // Named channels use specific-name tags; genre channels use IA subject strings (curl-verified).
        Channel(
            id: "greek-philosophy",
            name: "Greek Philosophy",
            category: "Audiobooks",
            icon: "building.columns",
            tags: ["plato", "socrates", "aristotle"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "chinese-philosophy",
            name: "Chinese Philosophy",
            category: "Audiobooks",
            icon: "circle.lefthalf.filled",
            tags: ["confucius", "tao", "chinese philosophy"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "chinese-history",
            name: "Chinese History",
            category: "Audiobooks",
            icon: "building.2",
            tags: ["china", "chinese history"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "greek-history",
            name: "Greek History",
            category: "Audiobooks",
            icon: "building.columns.fill",
            tags: ["herodotus", "greek history", "ancient greece"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-poetry", name: "Poetry", category: "Audiobooks",
            icon: "text.quote",
            tags: ["poetry"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-short-stories", name: "Short Stories", category: "Audiobooks",
            icon: "books.vertical",
            tags: ["short stories"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-nature", name: "Nature", category: "Audiobooks",
            icon: "leaf.fill",
            tags: ["nature"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-humor", name: "Humor & Satire", category: "Audiobooks",
            icon: "face.smiling",
            tags: ["humor"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-science-fiction", name: "Science Fiction", category: "Audiobooks",
            icon: "sparkles",
            tags: ["science fiction"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-travel", name: "Travel & Adventure", category: "Audiobooks",
            icon: "map.fill",
            tags: ["travel"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-biography", name: "Biography", category: "Audiobooks",
            icon: "person.text.rectangle.fill",
            tags: ["biography"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-drama", name: "Drama & Theater", category: "Audiobooks",
            icon: "theatermasks.fill",
            tags: ["drama"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-philosophy", name: "Philosophy", category: "Audiobooks",
            icon: "lightbulb.fill",
            tags: ["philosophy"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-religion", name: "Religion & Spirituality", category: "Audiobooks",
            icon: "rays",
            tags: ["religion"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-science", name: "Science & Technology", category: "Audiobooks",
            icon: "atom",
            tags: ["science"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-essays", name: "Essays & Speeches", category: "Audiobooks",
            icon: "doc.text.fill",
            tags: ["essays"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-historical-fiction", name: "Historical Fiction", category: "Audiobooks",
            icon: "clock.arrow.circlepath",
            tags: ["historical fiction"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-fairy-tales", name: "Fairy Tales", category: "Audiobooks",
            icon: "wand.and.stars",
            tags: ["fairy tales"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-art", name: "Art & Music", category: "Audiobooks",
            icon: "paintbrush.fill",
            tags: ["art"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-ghost-stories", name: "Ghost Stories", category: "Audiobooks",
            icon: "moon.stars.fill",
            tags: ["ghost stories"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-folklore", name: "Folklore & Legends", category: "Audiobooks",
            icon: "globe.europe.africa",
            tags: ["folklore"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-mythology", name: "Mythology", category: "Audiobooks",
            icon: "building.columns",
            tags: ["mythology"],
            contentType: .spokenWord,
            spokenWordCollections: ["librivoxaudio"],
            preferredSource: "internet_archive"
        ),

        // MARK: Contemporary — Free Music Archive genre channels (all curl-verified)
        Channel(
            id: "fma-classical", name: "Classical", category: "Contemporary",
            icon: "music.quarternote.3", tags: ["classical"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-jazz", name: "Jazz", category: "Contemporary",
            icon: "music.mic", tags: ["jazz"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-blues", name: "Blues", category: "Contemporary",
            icon: "guitars", tags: ["blues"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-rock", name: "Rock", category: "Contemporary",
            icon: "bolt.fill", tags: ["rock"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-country", name: "Country", category: "Contemporary",
            icon: "leaf", tags: ["country"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-folk", name: "Folk", category: "Contemporary",
            icon: "music.note", tags: ["folk"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-instrumental", name: "Instrumental", category: "Contemporary",
            icon: "tuningfork", tags: ["instrumental"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-electronic", name: "Electronic", category: "Contemporary",
            icon: "dot.radiowaves.left.and.right", tags: ["electronic"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-hip-hop", name: "Hip-Hop", category: "Contemporary",
            icon: "mic.fill", tags: ["hip-hop"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-pop", name: "Pop", category: "Contemporary",
            icon: "star.fill", tags: ["pop"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-soul-rnb", name: "Soul & R&B", category: "Contemporary",
            icon: "heart.fill", tags: ["soul"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-experimental", name: "Experimental", category: "Contemporary",
            icon: "wand.and.stars", tags: ["experimental"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-international", name: "World Music", category: "Contemporary",
            icon: "globe", tags: ["world music"],
            preferredSource: "fma"
        ),
        Channel(
            id: "fma-old-time", name: "Old-Time & Historic", category: "Contemporary",
            icon: "guitars", tags: ["old-time"],
            preferredSource: "fma"
        ),

        // MARK: Lectures — University of Oxford open-license audio lectures
        // Each channel's tags contain the podcasts.ox.ac.uk unit slug.
        Channel(
            id: "oxford-philosophy", name: "Philosophy", category: "Lectures",
            icon: "quote.bubble", tags: ["faculty-philosophy"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-history", name: "History", category: "Lectures",
            icon: "scroll", tags: ["faculty-history"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-english", name: "English Literature", category: "Lectures",
            icon: "books.vertical",
            tags: ["faculty-english-language-and-literature"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-torch", name: "TORCH — Humanities Research",
            category: "Lectures", icon: "lightbulb",
            tags: ["oxford-research-centre-humanities-torch"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-classics", name: "Classics", category: "Lectures",
            icon: "building.columns.fill", tags: ["faculty-classics"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-music", name: "Music", category: "Lectures",
            icon: "music.note.list", tags: ["faculty-music"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-physics", name: "Physics", category: "Lectures",
            icon: "atom", tags: ["department-physics"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-computer-science", name: "Computer Science",
            category: "Lectures", icon: "laptopcomputer",
            tags: ["department-computer-science"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-maths", name: "Mathematics", category: "Lectures",
            icon: "function", tags: ["mathematical-institute"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-engineering", name: "Engineering Science",
            category: "Lectures", icon: "gear",
            tags: ["department-engineering-science"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-chemistry", name: "Chemistry", category: "Lectures",
            icon: "drop.fill", tags: ["department-chemistry"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-business", name: "Saïd Business School",
            category: "Lectures", icon: "briefcase",
            tags: ["said-business-school"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-martin", name: "Oxford Martin School",
            category: "Lectures", icon: "globe",
            tags: ["oxford-martin-school"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-education", name: "Education", category: "Lectures",
            icon: "graduationcap", tags: ["department-education"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-internet", name: "Internet Institute (OII)",
            category: "Lectures", icon: "network",
            tags: ["oxford-internet-institute"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-blavatnik", name: "Blavatnik School of Government",
            category: "Lectures", icon: "building.2.fill",
            tags: ["blavatnik-school-government"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-economics", name: "Economics", category: "Lectures",
            icon: "chart.bar.fill", tags: ["department-economics"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-clinical-medicine", name: "Clinical Medicine (NDM)",
            category: "Lectures", icon: "stethoscope",
            tags: ["nuffield-department-clinical-medicine"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-population-health", name: "Population Health",
            category: "Lectures", icon: "heart.fill",
            tags: ["nuffield-department-population-health"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-surgical", name: "Surgical Sciences",
            category: "Lectures", icon: "cross.fill",
            tags: ["nuffield-department-surgical-sciences"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-psychology", name: "Psychology", category: "Lectures",
            icon: "brain.head.profile",
            tags: ["department-experimental-psychology"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-anatomy", name: "Physiology, Anatomy & Genetics",
            category: "Lectures", icon: "figure.stand",
            tags: ["department-physiology-anatomy-and-genetics-dpag"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),

        // MARK: News — Public radio & international broadcaster RSS feeds (all live-verified)
        // feedURL drives PodcastRSSService; contentType = spokenWord for track-level navigation.
        // tags: [id] must match what PodcastRSSService stores in Track.tags so channel.matches()
        // correctly isolates each channel's episodes; preferredSource: "podcast" skips IA/FMA DB rows.
        Channel(
            id: "news-bbc-world", name: "BBC World News",
            category: "News", icon: "globe",
            tags: ["news-bbc-world"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://podcasts.files.bbci.co.uk/p02nq0gn.rss"
        ),
        Channel(
            id: "news-bbc-newsday", name: "BBC Newsday",
            category: "News", icon: "newspaper",
            tags: ["news-bbc-newsday"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://podcasts.files.bbci.co.uk/p002vsnk.rss"
        ),
        Channel(
            id: "news-nprup-first", name: "NPR Up First",
            category: "News", icon: "sunrise.fill",
            tags: ["news-nprup-first"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.npr.org/510318/podcast.xml"
        ),
        Channel(
            id: "news-pbs-newshour", name: "PBS NewsHour",
            category: "News", icon: "tv",
            tags: ["news-pbs-newshour"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.npr.org/510317/podcast.xml"
        ),
        Channel(
            id: "news-democracy-now", name: "Democracy Now!",
            category: "News", icon: "megaphone.fill",
            tags: ["news-democracy-now"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://www.democracynow.org/podcast.xml"
        ),
        Channel(
            id: "news-un", name: "UN News",
            category: "News", icon: "building.2.fill",
            tags: ["news-un"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://news.un.org/feed/subscribe/en/news/all/rss.xml"
        ),
        Channel(
            id: "news-cbc-frontburner", name: "CBC Front Burner",
            category: "News", icon: "flame.fill",
            tags: ["news-cbc-frontburner"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://www.cbc.ca/podcasting/includes/frontburner.xml"
        ),
        Channel(
            id: "news-voa", name: "VOA Learning English",
            category: "News", icon: "waveform",
            tags: ["news-voa"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://learningenglish.voanews.com/podcast/?count=20"
        ),
        Channel(
            id: "news-npr-1a", name: "NPR 1A (Public Affairs)",
            category: "News", icon: "person.2.fill",
            tags: ["news-npr-1a"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.npr.org/510316/podcast.xml"
        ),
        Channel(
            id: "news-bbc-inourtime", name: "BBC In Our Time",
            category: "News", icon: "clock.fill",
            tags: ["news-bbc-inourtime"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://podcasts.files.bbci.co.uk/b006qykl.rss"
        ),
    ]

    // Ordered, deduplicated category names for section display.
    static var categories: [String] {
        var seen = Set<String>()
        return defaults.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}
