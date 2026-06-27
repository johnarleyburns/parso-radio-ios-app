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

        // MARK: Podcasts — freely-distributable spoken-word channels
        // feedURL drives PodcastRSSService; contentType = .spokenWord for track-level nav;
        // tags:[id] is the isolation stamp; preferredSource "podcast" skips IA/FMA DB rows;
        // imageURL is channel artwork for the browse grid. Episodes play 0:00→end (RSS ToS).
        // Curation bar: CC / public-domain / value-for-value / ad-free-or-host-read indie+nonprofit+
        // educational via open RSS. Host-read sponsors + publisher tracking prefixes tolerated (the
        // app adds no tracking of its own); big-commercial "personal-use-only" networks excluded.
        Channel(
            id: "news-democracy-now", name: "Democracy Now!",
            category: "Podcasts", icon: "megaphone.fill",
            tags: ["news-democracy-now"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://www.democracynow.org/podcast.xml",
            imageURL: "https://assets.democracynow.org/assets/DN-Podcast-AUDIO-1d5df65d8936dcfd1387274443b3e0713c5f15dd3fa400331229f4ab39b5c19e.jpg"
        ),
        Channel(
            id: "podcast-no-agenda", name: "No Agenda",
            category: "Podcasts", icon: "waveform.circle.fill",
            tags: ["podcast-no-agenda"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feed.nashownotes.com/rss.xml",
            summary: "A twice-weekly news deconstruction by Adam Curry and John C. Dvorak. No ads, no sponsors — listener-supported since 2007."
            // imageURL intentionally omitted — rotating per-episode art
        ),
        Channel(
            id: "podcast-citations-needed", name: "Citations Needed",
            category: "Podcasts", icon: "text.book.closed.fill",
            tags: ["podcast-citations-needed"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://citationsneeded.libsyn.com/rss",
            summary: "Nima Shirazi & Adam Johnson on media, PR, and power. Listener-funded via Patreon, no traditional ads.",
            imageURL: "https://static.libsyn.com/p/assets/6/6/8/9/6689195c7e4129ce/CN-3k.png"
        ),
        Channel(
            id: "podcast-security-now", name: "Security Now",
            category: "Podcasts", icon: "lock.shield.fill",
            tags: ["podcast-security-now"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/sn.xml",
            summary: "Steve Gibson and Leo Laporte break down the week's security news. CC BY-NC-ND, host-read sponsors.",
            imageURL: "https://elroy.twit.tv/sites/default/files/styles/twit_album_art_2048x2048/public/images/shows/security_now/album_art/audio/sn2022_albumart_standard_2400.jpg"
        ),
        Channel(
            id: "podcast-floss-weekly", name: "FLOSS Weekly",
            category: "Podcasts", icon: "apple.terminal.fill",
            tags: ["podcast-floss-weekly"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/floss.xml",
            summary: "Interviews with notable figures in the free and open-source software community. CC BY-NC-ND, ad-free.",
            imageURL: "https://elroy.twit.tv/sites/default/files/styles/twit_album_art_2048x2048/public/images/shows/floss_weekly/album_art/audio/floss2022_albumart_standard_2400.jpg"
        ),

        // ── Value-for-Value ─────────────────────────────────────────────
        Channel(
            id: "podcast-podcasting-2-0", name: "Podcasting 2.0",
            category: "Podcasts", icon: "dot.radiowaves.left.and.right",
            tags: ["podcast-podcasting-2-0"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://mp3s.nashownotes.com/pc20rss.xml",
            summary: "Adam Curry & Dave Jones on the open podcasting movement. Value-for-value, no ads, OP3 (open) analytics."
            // imageURL intentionally omitted — feed host blocks non-residential IPs
        ),

        // ── FOSS / open-source / privacy tech ───────────────────────────
        Channel(
            id: "podcast-changelog", name: "The Changelog",
            category: "Podcasts", icon: "chevron.left.forwardslash.chevron.right",
            tags: ["podcast-changelog"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://changelog.com/podcast/feed",
            summary: "Conversations with the people building open source. Open-licensed feed, OP3 analytics, host-read sponsors.",
            imageURL: "https://cdn.changelog.com/static/images/podcasts/podcast-original-f16d0363067166f241d080ee2e2d4a28.png"
        ),
        Channel(
            id: "podcast-go-time", name: "Go Time",
            category: "Podcasts", icon: "g.circle.fill",
            tags: ["podcast-go-time"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://changelog.com/gotime/feed",
            summary: "Panel discussion on the Go programming language. OP3 (open) analytics, host-read sponsors.",
            imageURL: "https://cdn.changelog.com/uploads/covers/go-time-original.png?v=63725770357"
        ),
        Channel(
            id: "podcast-js-party", name: "JS Party",
            category: "Podcasts", icon: "curlybraces",
            tags: ["podcast-js-party"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://changelog.com/jsparty/feed",
            summary: "Web development, JavaScript, and the front end. OP3 (open) analytics, host-read sponsors.",
            imageURL: "https://cdn.changelog.com/uploads/covers/js-party-original.png?v=63725770332"
        ),
        Channel(
            id: "podcast-practical-ai", name: "Practical AI",
            category: "Podcasts", icon: "cpu.fill",
            tags: ["podcast-practical-ai"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://changelog.com/practicalai/feed",
            summary: "Making AI practical, productive, and accessible. Open-licensed feed, host-read sponsors.",
            imageURL: "https://img.transistorcdn.com/WMlp2ug34XB6LDJ3-vnzti_-_y144LUlFW0Xzzn3fss/rs:fill:0:0:1/w:1400/h:1400/q:60/mb:500000/aHR0cHM6Ly9pbWct/dXBsb2FkLXByb2R1/Y3Rpb24udHJhbnNp/c3Rvci5mbS8wMTZi/ZWJmNWIwNDdmYTcw/NGJjMTExZjNjZmYy/M2ZjNS5wbmc.jpg"
        ),
        Channel(
            id: "podcast-talk-python", name: "Talk Python To Me",
            category: "Podcasts", icon: "terminal.fill",
            tags: ["podcast-talk-python"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://talkpython.fm/episodes/rss",
            summary: "Interviews on Python and its ecosystem. Freely distributed via open RSS, host-read sponsors.",
            imageURL: "https://cdn-podcast.talkpython.fm/static/img/talk-python-3000.jpg"
        ),
        Channel(
            id: "podcast-linux-unplugged", name: "LINUX Unplugged",
            category: "Podcasts", icon: "powerplug.fill",
            tags: ["podcast-linux-unplugged"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.fireside.fm/linuxunplugged/rss",
            summary: "A lively weekly Linux talk show. Public-domain-declared + value-for-value, host-read sponsors.",
            imageURL: "https://assets.fireside.fm/file/fireside-images/podcasts/images/f/f31a453c-fa15-491f-8618-3f71f1d565e5/cover.jpg"
        ),
        Channel(
            id: "podcast-self-hosted", name: "Self-Hosted",
            category: "Podcasts", icon: "server.rack",
            tags: ["podcast-self-hosted"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.fireside.fm/selfhosted/rss",
            summary: "A show about owning your data and running your own services. Host-read sponsors, Fireside CDN.",
            imageURL: "https://media24.fireside.fm/file/fireside-images-2024/podcasts/images/7/7296e34a-2697-479a-adfb-ad32329dd0b0/cover.jpg?v=2"
        ),
        Channel(
            id: "podcast-coder-radio", name: "Coder Radio",
            category: "Podcasts", icon: "keyboard.fill",
            tags: ["podcast-coder-radio"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.fireside.fm/coder/rss",
            summary: "A weekly talk show on the business and practice of software development. Host-read sponsors.",
            imageURL: "https://media24.fireside.fm/file/fireside-images-2024/podcasts/images/b/b44de5fa-47c1-4e94-bf9e-c72f8d1c8f5d/cover.jpg?v=8"
        ),

        // ── Apple / iOS / indie dev ─────────────────────────────────────
        Channel(
            id: "podcast-atp", name: "Accidental Tech Podcast",
            category: "Podcasts", icon: "laptopcomputer",
            tags: ["podcast-atp"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://atp.fm/rss",
            summary: "Tech, Apple, and programming with Marco Arment, Casey Liss, John Siracusa. Served direct from atp.fm, member-supported, host-read sponsors.",
            imageURL: "https://cdn.atp.fm/artwork"
        ),
        Channel(
            id: "podcast-under-the-radar", name: "Under the Radar",
            category: "Podcasts", icon: "hammer.fill",
            tags: ["podcast-under-the-radar"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://www.relay.fm/radar/feed",
            summary: "Marco Arment & David Smith on independent iOS app development. Host-read sponsors.",
            imageURL: "https://relayfm.s3.amazonaws.com/uploads/broadcast/image/23/radar_artwork_06e0e2c2-772f-48d8-b56e-77b1227bb76c.png"
        ),
        Channel(
            id: "podcast-connected", name: "Connected",
            category: "Podcasts", icon: "link.circle.fill",
            tags: ["podcast-connected"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://www.relay.fm/connected/feed",
            summary: "Apple news and analysis with Federico Viticci, Myke Hurley, Stephen Hackett. Host-read sponsors.",
            imageURL: "https://files.relay.fm/uploads/broadcast/image/5/connected_artwork_82973540-95cb-4452-a433-70fe9032cf60.png"
        ),

        // ── Tech news / commentary (CC BY-NC-ND, TWiT) ──────────────────
        Channel(
            id: "podcast-twit", name: "This Week in Tech",
            category: "Podcasts", icon: "newspaper.fill",
            tags: ["podcast-twit"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/twit.xml",
            summary: "The week's tech news in a roundtable. CC BY-NC-ND, host-read sponsors.",
            imageURL: "https://elroy.twit.tv/sites/default/files/styles/twit_album_art_2048x2048/public/images/shows/this_week_in_tech/album_art/audio/twit_2022albumart_standard_2048.jpg"
        ),
        Channel(
            id: "podcast-intelligent-machines", name: "Intelligent Machines",
            category: "Podcasts", icon: "gearshape.2.fill",
            tags: ["podcast-intelligent-machines"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/twig.xml",
            summary: "AI and the future of technology (formerly This Week in Google). CC BY-NC-ND, host-read sponsors.",
            imageURL: "https://elroy.twit.tv/sites/default/files/styles/twit_album_art_2048x2048/public/images/shows/Intelligent%20Machines/album_art/audio/IM_albumart_standard_0.jpg"
        ),
        Channel(
            id: "podcast-tech-news-weekly", name: "Tech News Weekly",
            category: "Podcasts", icon: "newspaper.circle.fill",
            tags: ["podcast-tech-news-weekly"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/tnw.xml",
            summary: "Interviews with the journalists who write the tech news. CC BY-NC-ND, host-read sponsors.",
            imageURL: "https://elroy.twit.tv/sites/default/files/styles/twit_album_art_2048x2048/public/images/shows/tech_news_weekly/album_art/audio/tnw2022_albumart_standard_2400.jpg"
        ),
        Channel(
            id: "podcast-macbreak-weekly", name: "MacBreak Weekly",
            category: "Podcasts", icon: "desktopcomputer",
            tags: ["podcast-macbreak-weekly"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/mbw.xml",
            summary: "Apple news and opinion roundtable. CC BY-NC-ND, host-read sponsors.",
            imageURL: "https://elroy.twit.tv/sites/default/files/styles/twit_album_art_2048x2048/public/images/shows/macbreak_weekly/album_art/audio/mbw2022_albumart_standard_2400.jpg"
        ),
        Channel(
            id: "podcast-windows-weekly", name: "Windows Weekly",
            category: "Podcasts", icon: "macwindow",
            tags: ["podcast-windows-weekly"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/ww.xml",
            summary: "Microsoft news with Paul Thurrott & Richard Campbell. CC BY-NC-ND, host-read sponsors.",
            imageURL: "https://elroy.twit.tv/sites/default/files/styles/twit_album_art_2048x2048/public/images/shows/windows_weekly/album_art/audio/ww2022_albumart_standard_2400.jpg"
        ),
        Channel(
            id: "podcast-untitled-linux-show", name: "Untitled Linux Show",
            category: "Podcasts", icon: "command.square.fill",
            tags: ["podcast-untitled-linux-show"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/uls.xml",
            summary: "Weekly Linux news and tips. CC BY-NC-ND, host-read sponsors.",
            imageURL: "https://elroy.twit.tv/sites/default/files/styles/twit_album_art_2048x2048/public/images/shows/Untitled%20Linux%20Show/album_art/audio/uls_albumart_2400_0.jpg"
        ),
        Channel(
            id: "podcast-hands-on-mac", name: "Hands-On Mac",
            category: "Podcasts", icon: "macbook",
            tags: ["podcast-hands-on-mac"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.twit.tv/hom.xml",
            summary: "Tips and tutorials for Apple devices. CC BY-NC-ND, host-read sponsors.",
            imageURL: "https://elroy.twit.tv/sites/default/files/styles/twit_album_art_2048x2048/public/images/shows/Hands-On%20Apple/album_art/audio/HOA_3000_audio_0.jpg"
        ),

        // ── Ideas / philosophy / economics / history ────────────────────
        Channel(
            id: "podcast-econtalk", name: "EconTalk",
            category: "Podcasts", icon: "chart.line.uptrend.xyaxis",
            tags: ["podcast-econtalk"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://feeds.simplecast.com/wgl4xEgL",
            summary: "Russ Roberts in long-form conversation on economics, ideas, and life. Ad-free, funded by Liberty Fund.",
            imageURL: "https://image.simplecastcdn.com/images/4ca709a1-1918-43a4-9035-1176b5aa9f2b/b8c673f8-58e7-4d4a-ab02-f83c2fd463c4/3000x3000/econtalknewbluecover1400.jpg?aid=rss_feed"
        ),
        Channel(
            id: "podcast-conversations-tyler", name: "Conversations with Tyler",
            category: "Podcasts", icon: "bubble.left.and.bubble.right.fill",
            tags: ["podcast-conversations-tyler"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://cowenconvos.libsyn.com/rss",
            summary: "Tyler Cowen interviews leading thinkers. Ad-free, produced by the Mercatus Center.",
            imageURL: "https://static.libsyn.com/p/assets/7/1/7/b/717bd07f94e956cea04421dee9605cbd/CWT_-_Podcast_Art_-_3000x3000.jpg"
        ),
        Channel(
            id: "podcast-in-our-time", name: "In Our Time",
            category: "Podcasts", icon: "building.columns.fill",
            tags: ["podcast-in-our-time"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://podcasts.files.bbci.co.uk/b006qykl.rss",
            summary: "Melvyn Bragg & guests on the history of ideas. Ad-free, served from BBC's own CDN.",
            imageURL: "https://ichef.bbci.co.uk/images/ic/3000x3000/p0m1q0p7.jpg"
        ),
        Channel(
            id: "podcast-philosophy-bites", name: "Philosophy Bites",
            category: "Podcasts", icon: "quote.bubble.fill",
            tags: ["podcast-philosophy-bites"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://philosophybites.libsyn.com/rss",
            summary: "Short interviews with top philosophers by Nigel Warburton & David Edmonds. Ad-free, donation-supported.",
            imageURL: "https://static.libsyn.com/p/assets/6/6/2/9/6629afb289ae5c80/philo_bites.jpg"
        ),
        Channel(
            id: "podcast-philosophize-this", name: "Philosophize This!",
            category: "Podcasts", icon: "brain.head.profile",
            tags: ["podcast-philosophize-this"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://philosophizethis.libsyn.com/rss",
            summary: "Stephen West's chronological tour through the history of philosophy. Ad-free, listener-supported.",
            imageURL: "https://static.libsyn.com/p/assets/1/d/9/4/1d946f34af4d1ee6/logo1.jpg"
        ),
        Channel(
            id: "podcast-revolutions", name: "Revolutions",
            category: "Podcasts", icon: "flag.fill",
            tags: ["podcast-revolutions"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://revolutionspodcast.libsyn.com/rss",
            summary: "Mike Duncan's narrative history of political revolutions — a complete 10-series archive. Ad-light.",
            imageURL: "https://static.libsyn.com/p/assets/3/4/5/f/345fbd6a253649c0/RevolutionsLogo_V2.jpg"
        ),

        // ── Public domain / government / science ────────────────────────
        Channel(
            id: "podcast-nasa-curious-universe", name: "NASA's Curious Universe",
            category: "Podcasts", icon: "moon.stars.fill",
            tags: ["podcast-nasa-curious-universe"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://nasa.gov/rss/universe_podcast.rss",
            summary: "NASA scientists and astronauts on space and science. Public domain (US gov work); audio via chrt.fm.",
            imageURL: "https://megaphone.imgix.net/podcasts/3c25fbae-6a1b-11ef-b25e-33943a7bea28/image/aa7a5b25380eed0aace9ed40435dbe04.png?ixlib=rails-4.3.1&max-w=3000&max-h=3000&fit=crop&auto=format,compress"
        ),
        Channel(
            id: "podcast-nasa-houston", name: "Houston We Have a Podcast",
            category: "Podcasts", icon: "globe.americas.fill",
            tags: ["podcast-nasa-houston"],
            contentType: .spokenWord, preferredSource: "podcast",
            feedURL: "https://www.nasa.gov/rss/dyn/Houston-We-Have-a-Podcast.rss",
            summary: "NASA's official human-spaceflight podcast from Johnson Space Center. Public domain (US gov work); audio via Megaphone.",
            imageURL: "https://megaphone.imgix.net/podcasts/65e4d56e-6a1b-11ef-b576-83eaa7bf6c9e/image/908e541f8bbe46d55e84129c5fb3d3c0.png?ixlib=rails-4.3.1&max-w=3000&max-h=3000&fit=crop&auto=format,compress"
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
