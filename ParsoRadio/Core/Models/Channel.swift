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

    init(
        id: String, name: String, category: String, icon: String,
        composers: [String] = [], instruments: [String] = [], tags: [String] = [],
        excludeTags: [String] = [],
        contentType: ContentType = .music, spokenWordCollections: [String] = [],
        preferredSource: String? = nil, feedURL: String? = nil,
        isDownloaded: Bool = false, minTrackDuration: Double? = nil,
        summary: String? = nil
    ) {
        self.id = id; self.name = name; self.category = category; self.icon = icon
        self.composers = composers; self.instruments = instruments; self.tags = tags
        self.excludeTags = excludeTags
        self.contentType = contentType; self.spokenWordCollections = spokenWordCollections
        self.preferredSource = preferredSource; self.feedURL = feedURL
        self.isDownloaded = isDownloaded
        self.minTrackDuration = minTrackDuration
        self.summary = summary
    }

    var iaQueryEntry: IAQueryEntry? { IAQueryRegistry.shared.entry(for: id) }

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
        case "Contemporary":
            return "\(name) from the Free Music Archive — Creative Commons recordings by independent artists."
        case "Lectures":
            return "\(name): lectures and talks from the University of Oxford's public podcast series."
        case "News":
            return "The latest episodes from \(name) — refreshed to the newest item each time you tune in."
        case "Audiobooks":
            return "\(name) audiobooks read by LibriVox volunteers — public-domain literature, a new book each time."
        case "Ambient":
            return "A continuous \(name.lowercased()) soundscape for focus, relaxation, or sleep."
        default:
            return "A hand-curated Internet Archive channel of \(name) recordings."
        }
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
            tags: ["spanish-guitar"],
            preferredSource: "internet_archive",
            summary: "Spanish & classical guitar — the great guitarists (Segovia, Yepes, Bream, the Romeros, Sainz de la Maza, Tárrega, Paco de Lucía, Sabicas, Montoya, Barrueco, Russell) and the core repertoire (Sor, Albéniz, Granados, Rodrigo, Barrios, Villa-Lobos). Matched by guitarist or by an explicit guitar title; orchestral, piano, vocal and non-guitar works are excluded."
        ),
        // Chamber Music: curl-verified 2026-05-15 — 919 items; canonical
        // ensembles (Budapest/Quartetto Italiano), Trout Quintet, Beethoven
        // late quartets; zero AI/jazz/radio noise.
        Channel(
            id: "chamber-music", name: "Chamber Music", category: "Curated",
            icon: "music.quarternote.3",
            tags: ["chamber music", "string quartet", "piano trio"],
            preferredSource: "internet_archive",
            summary: "Intimate ensemble music — string quartets, piano trios and quintets by Beethoven, Brahms, Mozart, Schubert, Dvořák and more. No jazz, AI tracks, or radio noise."
        ),
        // Historical Voices: curl-verified 2026-05-15 — 2716 items; Pacifica
        // Radio Archives + Freedom Archives interviews/public-affairs (Sontag,
        // Vidal, Churchill, Clarke, civil-rights & Vietnam-era recordings).
        Channel(
            id: "historical-voices", name: "Historical Voices", category: "Curated",
            icon: "mic",
            tags: ["interview", "public affairs", "history"],
            preferredSource: "internet_archive",
            summary: "Archival interviews and public-affairs recordings from the Pacifica Radio and Freedom Archives — civil-rights, Vietnam-era and 20th-century cultural voices."
        ),
        // Symphony Orchestra: curl-verified 2026-05-15 — 889 items; orchestral
        // symphonies/concertos/overtures (Beethoven, Mahler, Shostakovich,
        // Szell-Cleveland); chamber/vocal/jazz/soundtrack excluded.
        Channel(
            id: "symphony-orchestra", name: "Symphony Orchestra", category: "Curated",
            icon: "music.note.list",
            tags: ["symphony", "orchestra", "concerto"],
            preferredSource: "internet_archive",
            summary: "Full-orchestra symphonies, concertos and overtures — Beethoven, Mahler, Shostakovich and the great conductors. Chamber, vocal, jazz and soundtrack works are excluded."
        ),
        // Piano Hour: curl-verified 2026-05-15 — 1192 items; solo piano
        // (sonatas, nocturnes, études, Chopin/Liszt/Debussy/Beethoven);
        // jazz/ragtime/orchestral/vocal and religious collections excluded.
        Channel(
            id: "piano-hour", name: "Piano Hour", category: "Curated",
            icon: "pianokeys",
            tags: ["piano", "piano sonata", "nocturne"],
            preferredSource: "internet_archive",
            summary: "Solo piano — sonatas, nocturnes and études from Chopin, Liszt, Debussy and Beethoven. Jazz, ragtime, orchestral and vocal works are excluded."
        ),
        // Tribal Works: curl-verified 2026-05-15 — 2324 items; ethnomusicology
        // / world traditional & field recordings (gamelan, West-African,
        // Native American, Autry collection); new-age/ambient/spoken excluded.
        Channel(
            id: "tribal-works", name: "Tribal Works", category: "Curated",
            icon: "globe",
            tags: ["ethnomusicology", "world music", "field recording"],
            preferredSource: "internet_archive",
            summary: "Traditional and Indigenous music from around the world — gamelan, West-African, Native American and ethnographic field recordings. New-age and ambient remixes are excluded."
        ),
        // Café Lento: curl-verified 2026-05-15 — 882 items; mellow bossa /
        // cool & chamber jazz / solo guitar (Laurindo Almeida, Bill Evans,
        // André Previn); bebop/rock/electronic/big-band excluded.
        Channel(
            id: "cafe-lento", name: "Café Lento", category: "Curated",
            icon: "cup.and.saucer",
            tags: ["bossa nova", "cool jazz", "lounge"],
            preferredSource: "internet_archive",
            summary: "Mellow café listening — bossa nova, cool and chamber jazz, and soft solo guitar (Laurindo Almeida, Bill Evans, André Previn). Bebop, rock and big-band are excluded."
        ),
        // Netlabels: the entire IA netlabels collection, randomized
        // (curl-verified 2026-05-16 — 78,120 audio items).
        Channel(
            id: "netlabels", name: "Netlabels", category: "Curated",
            icon: "dot.radiowaves.left.and.right",
            tags: ["netlabels"],
            preferredSource: "internet_archive",
            summary: "The Internet Archive's vast Netlabels collection — free, Creative-Commons releases from independent net-labels spanning every electronic and indie genre, shuffled."
        ),
        // 78 RPM: the entire IA 78rpm collection, randomized (309,347 items).
        Channel(
            id: "rpm-78", name: "78 RPM", category: "Curated",
            icon: "opticaldisc",
            tags: ["78rpm", "shellac"],
            preferredSource: "internet_archive",
            summary: "Crackle and charm from the shellac era — the Internet Archive's enormous 78 RPM collection of early-20th-century recordings, shuffled."
        ),
        // Religious Music: sacred/liturgical music across faiths (Christian
        // sacred choral, Gregorian chant, hymns, spirituals; Hindu bhajan &
        // kirtan; Sufi qawwali; Jewish cantorial; Buddhist chant). Sermons
        // and lectures explicitly excluded — music only. Curl-verified
        // 2026-05-21 — 3,606 items.
        Channel(
            id: "religious-music", name: "Religious Music", category: "Curated",
            icon: "music.quarternote.3",
            tags: ["religious-music"],
            preferredSource: "internet_archive",
            summary: "Sacred and devotional music across faiths — Gregorian chant, Christian sacred choral works, hymns and spirituals, Hindu bhajan and kirtan, Sufi qawwali, Jewish cantorial, Buddhist chant. Music only; sermons and lectures are excluded."
        ),
        // Children's Songs: two safe arms — vintage 78rpm nursery-rhyme
        // records (phrase-title matched) + the curated subject:"kids music"
        // tag (PBS/Nick Jr./Disney/indie kids comps). netlabels excluded
        // (profane releases); LibriVox/audiobooks/books excluded so it stays
        // MUSIC, not spoken-word.
        Channel(
            id: "childrens-songs", name: "Children's Songs", category: "Curated",
            icon: "music.note.house.fill",
            tags: ["childrens-songs"],
            preferredSource: "internet_archive",
            minTrackDuration: 60,   // drop sub-minute noise clips
            summary: "Family-friendly children's music — vintage nursery-rhyme 78s and curated kids' compilations. Content is filtered for a young audience."
        ),
        // Curated book channels — explicit author/work allowlists (LibriVox,
        // English). Like all book channels they play a book's FIRST track;
        // the user adds the whole book to a playlist if they want it.
        Channel(
            id: "ancient-greece", name: "Ancient Greece", category: "Curated",
            icon: "building.columns", tags: ["ancient-greece"],
            contentType: .spokenWord, preferredSource: "internet_archive",
            summary: "LibriVox readings of ancient Greek literature and philosophy — Homer, Plato, the tragedians and more, in English and Greek. Plays the first part of each work."
        ),
        Channel(
            id: "great-books", name: "Great Books", category: "Curated",
            icon: "books.vertical", tags: ["great-books"],
            contentType: .spokenWord, preferredSource: "internet_archive",
            summary: "LibriVox recordings from the Great Books canon — the foundational works of philosophy, science and literature. Plays a book's first part; add the whole book to a playlist to continue."
        ),
        Channel(
            id: "greater-books", name: "Greater Books", category: "Curated",
            icon: "text.book.closed", tags: ["greater-books"],
            contentType: .spokenWord, preferredSource: "internet_archive",
            summary: "A broader literary canon (the greaterbooks.com list) read by LibriVox volunteers — the world's essential novels, plays and poetry. Plays each work's first part."
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
            id: "childrens-books", name: "Children's Books", category: "Curated",
            icon: "books.vertical.fill", tags: ["childrens-books"],
            contentType: .spokenWord, preferredSource: "internet_archive",
            summary: "Classic children's stories and fairy tales read aloud by LibriVox volunteers. Plays the first part of each book; add the whole book to a playlist to keep going."
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
