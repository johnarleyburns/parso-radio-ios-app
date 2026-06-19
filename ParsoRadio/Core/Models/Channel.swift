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
    // If set, a track shorter than this many seconds is auto-skipped (used by
    // Children's Songs to drop sub-minute noise clips — IA exposes no
    // item-level runtime, so this is enforced once the player knows duration).
    let minTrackDuration: Double?
    // Short user-facing blurb for ChannelInfoView. Falls back to
    // `detailDescription` (derived from composers / instruments / tags) when nil.
    let summary: String?
    // Auto-seek past introductory filler for news/podcast channels.
    // Channels with this set start playback at the given second offset.
    let startOffsetSeconds: Double?
    // Optional external image URL for channel-level artwork (podcast show art, etc.)
    let imageURL: String?
    // Custom IA query (curated/user-created channels that aren't in ia_queries.json).
    let iaQuery: String?

    init(
        id: String, name: String, category: String, icon: String,
        composers: [String] = [], instruments: [String] = [], tags: [String] = [],
        excludeTags: [String] = [],
        contentType: ContentType = .music, spokenWordCollections: [String] = [],
        preferredSource: String? = nil, feedURL: String? = nil,
        isDownloaded: Bool = false, minTrackDuration: Double? = nil,
        summary: String? = nil, startOffsetSeconds: Double? = nil,
        imageURL: String? = nil, iaQuery: String? = nil
    ) {
        self.id = id; self.name = name; self.category = category; self.icon = icon
        self.composers = composers; self.instruments = instruments; self.tags = tags
        self.excludeTags = excludeTags
        self.contentType = contentType; self.spokenWordCollections = spokenWordCollections
        self.preferredSource = preferredSource; self.feedURL = feedURL
        self.isDownloaded = isDownloaded
        self.minTrackDuration = minTrackDuration
        self.summary = summary
        self.startOffsetSeconds = startOffsetSeconds
        self.imageURL = imageURL
        self.iaQuery = iaQuery
    }

    var iaQueryEntry: IAQueryEntry? {
        if let entry = IAQueryRegistry.shared.entry(for: id) { return entry }
        if let q = iaQuery { return IAQueryEntry(channelId: id, iaQuery: q, matchTags: [id]) }
        return nil
    }

    // The per-channel isolation stamp injected onto registry tracks. It is
    // namespaced so it can NEVER collide with a natural IA subject value —
    // bare ids like "lofi"/"netlabels" ARE real IA subjects and were leaking
    // other channels' tracks into those channels.
    static func stampToken(_ id: String) -> String { "pmreg::\(id)" }

    func matches(_ track: Track) -> Bool {
        // Pure-Lucene registry channels isolate STRICTLY by their injected
        // stamp. The descriptive `tags` are display-only and must NOT be used
        // for matching: generic words collide across channels in the shared DB
        // (e.g. a Spanish-Guitar "Concierto de Aranjuez" track carries the IA
        // subject "concerto", which would otherwise leak it into Symphony
        // Orchestra). The stamp is unique per channel and injected only into
        // that channel's fetched tracks, so it cannot cross-contaminate.
        if let entry = iaQueryEntry {
            return entry.matchTags.contains { track.tags.contains(Channel.stampToken($0)) }
        }
        // Non-registry channels (FMA, Lectures, News, Ambient) match by tag.
        if composers.isEmpty && instruments.isEmpty {
            return tags.isEmpty || tags.contains(where: { track.tags.contains($0) })
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

    /// A complete, user-facing sentence describing the channel for
    /// ChannelInfoView. Uses the hand-written `summary` when present, else a
    /// per-category template so EVERY channel reads as a real sentence.
    var infoSentence: String {
        if let s = summary, !s.isEmpty { return s }
        switch category {
        case "Lectures":
            return "\(name): lectures and talks from the University of Oxford's public podcast series."
        case "Podcasts":
            return "The latest episodes from \(name) — refreshed to the newest item each time you tune in."
        case "Audiobooks":
            return "\(name) audiobooks read by LibriVox volunteers — public-domain literature, a new book each time."
        case "Ambient":
            return "A continuous \(name.lowercased()) soundscape for focus, relaxation, or sleep."
        case "Curated Music":
            return "Music from the \(name) collection on the Internet Archive."
        default:
            return "An Internet Archive channel of \(name) recordings."
        }
    }
}

extension Channel {
    static let defaults: [Channel] = [

        // MARK: For You — dynamic, built from listening history at fetch time
        // (no static ia_queries.json entry). Show a "listen to N tracks first"
        // prompt until there's enough history. See RecommendationQueryBuilder.
        Channel(
            id: "for-you", name: "For You", category: "For You",
            icon: "sparkles",
            tags: ["for-you"],
            preferredSource: "internet_archive",
            summary: "A rotating mix of music and audiobooks based on your listening history. Updates as you listen."
        ),
        // Legacy individual channels — kept for backward compatibility with
        // existing playlists and references. Not shown in the Listen UI.
        Channel(
            id: "music-for-you", name: "Music for You", category: "For You",
            icon: "sparkles",
            tags: ["music-for-you"],
            preferredSource: "internet_archive",
            summary: "A rotating mix based on the music you play most — more from the artists, composers and genres in your listening history. Updates as you listen."
        ),
        Channel(
            id: "books-for-you", name: "Books for You", category: "For You",
            icon: "sparkles",
            tags: ["books-for-you"],
            contentType: .spokenWord,
            preferredSource: "internet_archive",
            summary: "Audiobooks picked from the authors and genres you've been listening to. Updates as you listen."
        ),

        // MARK: Lectures — University of Oxford open-license audio lectures
        // Each channel's tags contain the podcasts.ox.ac.uk unit slug.
        Channel(
            id: "oxford-business", name: "Business",
            category: "Lectures", icon: "briefcase",
            tags: ["said-business-school"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-chemistry", name: "Chemistry", category: "Lectures",
            icon: "drop.fill", tags: ["department-chemistry"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-classics", name: "Classics", category: "Lectures",
            icon: "building.columns.fill", tags: ["faculty-classics"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-computer-science", name: "Computer Science",
            category: "Lectures", icon: "laptopcomputer",
            tags: ["department-computer-science"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-economics", name: "Economics", category: "Lectures",
            icon: "chart.bar.fill", tags: ["department-economics"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-education", name: "Education", category: "Lectures",
            icon: "graduationcap", tags: ["department-education"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-engineering", name: "Engineering",
            category: "Lectures", icon: "gear",
            tags: ["department-engineering-science"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-english", name: "English Literature", category: "Lectures",
            icon: "books.vertical",
            tags: ["faculty-english-language-and-literature"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-history", name: "History", category: "Lectures",
            icon: "scroll", tags: ["faculty-history"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-torch", name: "Humanities",
            category: "Lectures", icon: "lightbulb",
            tags: ["oxford-research-centre-humanities-torch"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-maths", name: "Mathematics", category: "Lectures",
            icon: "function", tags: ["mathematical-institute"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-clinical-medicine", name: "Medicine",
            category: "Lectures", icon: "stethoscope",
            tags: ["nuffield-department-clinical-medicine"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-martin", name: "Oxford Martin School",
            category: "Lectures", icon: "globe",
            tags: ["oxford-martin-school"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-philosophy", name: "Philosophy", category: "Lectures",
            icon: "quote.bubble", tags: ["faculty-philosophy"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-physics", name: "Physics", category: "Lectures",
            icon: "atom", tags: ["department-physics"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-psychology", name: "Psychology", category: "Lectures",
            icon: "brain.head.profile",
            tags: ["department-experimental-psychology"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-anatomy", name: "The Human Body",
            category: "Lectures", icon: "figure.stand",
            tags: ["department-physiology-anatomy-and-genetics-dpag"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),
        Channel(
            id: "oxford-internet", name: "The Internet",
            category: "Lectures", icon: "network",
            tags: ["oxford-internet-institute"], contentType: .spokenWord,
            preferredSource: "oxford_lectures"
        ),

        // MARK: Podcasts — Ad-free, CC-licensed or donation-funded podcasts
        // Every podcast here is verified ad-free in its RSS feed.
        // feedURL drives PodcastRSSService; contentType = spokenWord for track-level
        // navigation. tags: [id] must match what PodcastRSSService stores in
        // Track.tags so channel.matches() correctly isolates each channel's episodes;
        // preferredSource: "podcast" skips IA/FMA DB rows.
        // Episodes play from 0:00 to comply with podcast RSS terms of service.
        Channel(
            id: "news-democracy-now", name: "Democracy Now!",
            category: "Podcasts", icon: "megaphone.fill",
            tags: ["news-democracy-now"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://www.democracynow.org/podcast.xml"
        ),
        Channel(
            id: "podcast-no-agenda", name: "No Agenda",
            category: "Podcasts", icon: "waveform.circle.fill",
            tags: ["podcast-no-agenda"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feed.nashownotes.com/rss.xml",
            summary: "A twice-weekly news deconstruction by Adam Curry and John C. Dvorak. No ads, no sponsors — listener-supported since 2007."
        ),
        Channel(
            id: "podcast-citations-needed", name: "Citations Needed",
            category: "Podcasts", icon: "text.book.closed.fill",
            tags: ["podcast-citations-needed"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.libsyn.com/169725/rss",
            summary: "A weekly podcast about media, power, and the history of bullshit. Ad-free, funded by listener donations."
        ),
        Channel(
            id: "podcast-security-now", name: "Security Now",
            category: "Podcasts", icon: "lock.shield.fill",
            tags: ["podcast-security-now"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/sn.xml",
            summary: "Steve Gibson and Leo Laporte break down the week's security news. CC BY-NC-SA, ad-free audio feed."
        ),
        Channel(
            id: "podcast-floss-weekly", name: "FLOSS Weekly",
            category: "Podcasts", icon: "apple.terminal.fill",
            tags: ["podcast-floss-weekly"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/floss.xml",
            summary: "Interviews with notable figures in the free and open-source software community. CC BY, ad-free."
        ),

        // MARK: Audiobooks — LibriVox via pure-Lucene IA registry
        // Each channel is a single curl-verified
        // `collection:librivoxaudio AND (subject:... OR ...)` query in
        // ia_queries.json, fetched with sort=random. tags:[id] is the
        // isolation stamp; .spokenWord persists position + audiobook UX.
        Channel(
            id: "lv-general-fiction", name: "General Fiction", category: "Audiobooks",
            icon: "book", tags: ["lv-general-fiction"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-literary-fiction", name: "Literary Fiction", category: "Audiobooks",
            icon: "books.vertical", tags: ["lv-literary-fiction"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-science-fiction", name: "Science Fiction", category: "Audiobooks",
            icon: "sparkles", tags: ["lv-science-fiction"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-horror-gothic", name: "Horror & Gothic", category: "Audiobooks",
            icon: "moon.stars.fill", tags: ["lv-horror-gothic"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-mystery-crime", name: "Mystery & Crime", category: "Audiobooks",
            icon: "magnifyingglass", tags: ["lv-mystery-crime"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-adventure", name: "Adventure", category: "Audiobooks",
            icon: "map.fill", tags: ["lv-adventure"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-fantasy-mythology", name: "Fantasy & Mythology", category: "Audiobooks",
            icon: "wand.and.stars", tags: ["lv-fantasy-mythology"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-romance", name: "Romance", category: "Audiobooks",
            icon: "heart.fill", tags: ["lv-romance"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-satire-humor", name: "Satire & Humor", category: "Audiobooks",
            icon: "face.smiling", tags: ["lv-satire-humor"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-war-military", name: "War & Military", category: "Audiobooks",
            icon: "shield.fill", tags: ["lv-war-military"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-short-stories", name: "Short Stories", category: "Audiobooks",
            icon: "doc.text", tags: ["lv-short-stories"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-drama-plays", name: "Drama & Plays", category: "Audiobooks",
            icon: "theatermasks.fill", tags: ["lv-drama-plays"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-travel", name: "Travel & Exploration", category: "Audiobooks",
            icon: "airplane", tags: ["lv-travel"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-ancient-world", name: "Ancient World", category: "Audiobooks",
            icon: "building.columns.fill", tags: ["lv-ancient-world"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-poetry", name: "Poetry", category: "Audiobooks",
            icon: "text.quote", tags: ["lv-poetry"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-philosophy-mind", name: "Philosophy & Mind", category: "Audiobooks",
            icon: "brain.head.profile", tags: ["lv-philosophy-mind"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-history", name: "History", category: "Audiobooks",
            icon: "scroll", tags: ["lv-history"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-biography", name: "Biography", category: "Audiobooks",
            icon: "person.text.rectangle", tags: ["lv-biography"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-science-nature", name: "Science & Nature", category: "Audiobooks",
            icon: "atom", tags: ["lv-science-nature"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-religion", name: "Religion & Scripture", category: "Audiobooks",
            icon: "book.closed.fill", tags: ["lv-religion"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),
        Channel(
            id: "lv-essays-ideas", name: "Essays & Ideas", category: "Audiobooks",
            icon: "lightbulb", tags: ["lv-essays-ideas"],
            contentType: .spokenWord, preferredSource: "internet_archive"
        ),

        // MARK: Ambient — nature sounds and single-track loops
        // Yellowstone: 114 NPS public-domain MP3s via AmbientStaticService (AWS CloudFront, no auth).
        // Loop channels: single CC0 track from Freesound CDN; contentType .ambientLoop
        // plays through AudioPlayerService's seamless AVAudioEngine crossfade-loop path.
        // tags:[id] + preferredSource isolate each channel in the DB (same pattern as News).
        Channel(
            id: "ambient-yellowstone", name: "Sounds of Yellowstone",
            category: "Ambient", icon: "mountain.2.fill",
            tags: ["yellowstone"],
            preferredSource: "nps"
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
