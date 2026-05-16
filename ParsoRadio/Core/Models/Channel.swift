import Foundation

enum ContentType: String, Codable {
    case music
    case spokenWord
    case ambientLoop  // single track repeated indefinitely
}

struct Channel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let icon: String          // SF Symbol name
    let composers: [String]
    let instruments: [String]
    let tags: [String]
    let excludeTags: [String]
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
        excludeTags: [String] = [],
        contentType: ContentType = .music, spokenWordCollections: [String] = [],
        preferredSource: String? = nil, feedURL: String? = nil, isDownloaded: Bool = false
    ) {
        self.id = id; self.name = name; self.category = category; self.icon = icon
        self.composers = composers; self.instruments = instruments; self.tags = tags
        self.excludeTags = excludeTags
        self.contentType = contentType; self.spokenWordCollections = spokenWordCollections
        self.preferredSource = preferredSource; self.feedURL = feedURL
        self.isDownloaded = isDownloaded
    }

    var iaQueryEntry: IAQueryEntry? { IAQueryRegistry.shared.entry(for: id) }

    func matches(_ track: Track) -> Bool {
        // Tag-only channels (no composer/instrument constraints) must match by tag.
        // matchTags from the IA query registry augment the channel's own tags so that
        // QueueManager correctly isolates registry-fetched tracks from the DB.
        let allTags = tags + (iaQueryEntry?.matchTags ?? [])
        if composers.isEmpty && instruments.isEmpty {
            return allTags.isEmpty || allTags.contains(where: { track.tags.contains($0) })
        }
        let composerMatch = composers.isEmpty || composers.contains(track.composer ?? "")
        let instrumentMatch = instruments.isEmpty
            || instruments.contains(where: { track.instruments.contains($0) })
        return composerMatch && instrumentMatch
    }

    var detailDescription: String {
        var parts: [String] = []
        if !composers.isEmpty {
            parts.append(composers.map { $0.capitalized }.joined(separator: ", "))
        }
        if !instruments.isEmpty {
            parts.append(instruments.map { $0.capitalized }.joined(separator: " & "))
        }
        if parts.isEmpty, !tags.isEmpty {
            parts.append(tags.prefix(2).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}

extension Channel {
    static let defaults: [Channel] = [

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
            icon: "guitars", tags: ["old-time__historic"],
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
            id: "news-npr-1a", name: "NPR 1A (Public Affairs)",
            category: "News", icon: "person.2.fill",
            tags: ["news-npr-1a"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.npr.org/510316/podcast.xml"
        ),

        // MARK: Curated — pure-Lucene IA channels
        // Each channel here resolves to ONE hand-tuned Lucene query in
        // Resources/ia_queries.json. There is NO code-side filtering: no
        // LicenseValidator rejection, no MetadataNormalizer/confidence gate,
        // no collection/category post-filter. The query is the entire curation;
        // matchTags is the per-channel isolation stamp injected at fetch time.
        // `tags` here only feed detailDescription/UI — matching uses the stamp.
        Channel(
            id: "spanish-guitar", name: "Spanish Guitar", category: "Curated",
            icon: "guitars",
            tags: ["spanish guitar", "classical guitar", "flamenco"],
            preferredSource: "internet_archive"
        ),
        // Chamber Music: curl-verified 2026-05-15 — 919 items; canonical
        // ensembles (Budapest/Quartetto Italiano), Trout Quintet, Beethoven
        // late quartets; zero AI/jazz/radio noise.
        Channel(
            id: "chamber-music", name: "Chamber Music", category: "Curated",
            icon: "music.quarternote.3",
            tags: ["chamber music", "string quartet", "piano trio"],
            preferredSource: "internet_archive"
        ),
        // Historical Voices: curl-verified 2026-05-15 — 2716 items; Pacifica
        // Radio Archives + Freedom Archives interviews/public-affairs (Sontag,
        // Vidal, Churchill, Clarke, civil-rights & Vietnam-era recordings).
        Channel(
            id: "historical-voices", name: "Historical Voices", category: "Curated",
            icon: "mic",
            tags: ["interview", "public affairs", "history"],
            preferredSource: "internet_archive"
        ),
        // Symphony Orchestra: curl-verified 2026-05-15 — 889 items; orchestral
        // symphonies/concertos/overtures (Beethoven, Mahler, Shostakovich,
        // Szell-Cleveland); chamber/vocal/jazz/soundtrack excluded.
        Channel(
            id: "symphony-orchestra", name: "Symphony Orchestra", category: "Curated",
            icon: "music.note.list",
            tags: ["symphony", "orchestra", "concerto"],
            preferredSource: "internet_archive"
        ),
        // Piano Hour: curl-verified 2026-05-15 — 1192 items; solo piano
        // (sonatas, nocturnes, études, Chopin/Liszt/Debussy/Beethoven);
        // jazz/ragtime/orchestral/vocal and religious collections excluded.
        Channel(
            id: "piano-hour", name: "Piano Hour", category: "Curated",
            icon: "pianokeys",
            tags: ["piano", "piano sonata", "nocturne"],
            preferredSource: "internet_archive"
        ),
        // Tribal Works: curl-verified 2026-05-15 — 2324 items; ethnomusicology
        // / world traditional & field recordings (gamelan, West-African,
        // Native American, Autry collection); new-age/ambient/spoken excluded.
        Channel(
            id: "tribal-works", name: "Tribal Works", category: "Curated",
            icon: "globe",
            tags: ["ethnomusicology", "world music", "field recording"],
            preferredSource: "internet_archive"
        ),
        // Café Lento: curl-verified 2026-05-15 — 882 items; mellow bossa /
        // cool & chamber jazz / solo guitar (Laurindo Almeida, Bill Evans,
        // André Previn); bebop/rock/electronic/big-band excluded.
        Channel(
            id: "cafe-lento", name: "Café Lento", category: "Curated",
            icon: "cup.and.saucer",
            tags: ["bossa nova", "cool jazz", "lounge"],
            preferredSource: "internet_archive"
        ),

        // MARK: Ambient — nature sounds, lofi, and single-track loops
        // Yellowstone: 114 NPS public-domain MP3s via AmbientStaticService (AWS CloudFront, no auth).
        // Lofi Cafe: FMA Lo-fi-Hip-Hop genre, CC0/CC-BY tracks.
        // Loop channels: single CC0 track from Freesound CDN; contentType .ambientLoop restarts on finish.
        // tags:[id] + preferredSource isolate each channel in the DB (same pattern as News).
        Channel(
            id: "ambient-yellowstone", name: "Sounds of Yellowstone",
            category: "Ambient", icon: "mountain.2.fill",
            tags: ["yellowstone"],
            preferredSource: "nps"
        ),
        Channel(
            id: "ambient-lofi", name: "Lofi Cafe",
            category: "Ambient", icon: "cup.and.saucer.fill",
            tags: ["lo-fi-hip-hop"],
            preferredSource: "fma"
        ),
        Channel(
            id: "ambient-flowing-water", name: "Flowing Water",
            category: "Ambient", icon: "drop.fill",
            tags: ["ambient-flowing-water"],
            contentType: .ambientLoop, preferredSource: "freesound"
        ),
        Channel(
            id: "ambient-rain", name: "Rainy Day",
            category: "Ambient", icon: "cloud.rain.fill",
            tags: ["ambient-rain"],
            contentType: .ambientLoop, preferredSource: "freesound"
        ),
        Channel(
            id: "ambient-ocean", name: "Ocean Waves",
            category: "Ambient", icon: "water.waves",
            tags: ["ambient-ocean"],
            contentType: .ambientLoop, preferredSource: "freesound"
        ),
    ]

    // Ordered, deduplicated category names for section display.
    static var categories: [String] {
        var seen = Set<String>()
        return defaults.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}
