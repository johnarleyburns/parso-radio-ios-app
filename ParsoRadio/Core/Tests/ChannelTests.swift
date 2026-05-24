import XCTest
@testable import ParsoMusic

final class ChannelTests: XCTestCase {

    func testDefaultChannelCount() {
        // 2 For You + 14 Contemporary + 18 Lectures + 4 News + 4 Ambient
        // + 14 Curated + 21 Audiobooks (LibriVox) = 77. (Dropped bulk Netlabels
        // & 78 RPM; added String Quartet + Music/Books for You.)
        XCTAssertEqual(Channel.defaults.count, 77)
    }

    func testEveryIAChannelIsPureLuceneRegistryBacked() {
        // Legacy Classical is gone. Audiobooks are back, but ONLY as
        // pure-Lucene registry channels — every internet_archive channel
        // (Curated music + LibriVox audiobooks) must have an ia_queries.json
        // entry whose stamp is its own id. No code-side filtered IA channels.
        XCTAssertTrue(Channel.defaults.allSatisfy { $0.category != "Classical" },
            "No legacy Classical channels should remain")
        for ch in Channel.defaults where ch.preferredSource == "internet_archive" {
            XCTAssertTrue(["Curated", "Audiobooks", "For You"].contains(ch.category),
                "IA channel '\(ch.id)' must be Curated, Audiobooks or For You")
            guard let entry = ch.iaQueryEntry else {
                XCTFail("IA channel '\(ch.id)' must be registry-backed"); continue
            }
            XCTAssertEqual(entry.matchTags, [ch.id],
                "IA channel '\(ch.id)' stamp must be [\(ch.id)]")
        }
    }

    func testForYouChannelsExistAndAreDynamic() {
        let ids = Set(Channel.defaults.filter { $0.category == "For You" }.map(\.id))
        XCTAssertEqual(ids, ["music-for-you", "books-for-you"])
        // Books-for-you is spoken-word so it gets ±15s lock-screen controls and
        // position persistence; music-for-you is music.
        let books = Channel.defaults.first { $0.id == "books-for-you" }
        XCTAssertEqual(books?.contentType, .spokenWord)
    }

    func testAudiobooksAreTwentyOneLibriVoxRegistryChannels() {
        let ab = Channel.defaults.filter { $0.category == "Audiobooks" }
        XCTAssertEqual(ab.count, 21, "Expected 21 LibriVox Audiobooks channels")
        for ch in ab {
            XCTAssertEqual(ch.contentType, .spokenWord,
                "Audiobook '\(ch.id)' must be .spokenWord (position persistence)")
            XCTAssertTrue(ch.id.hasPrefix("lv-"), "Audiobook id convention: \(ch.id)")
            XCTAssertNotNil(ch.iaQueryEntry,
                "Audiobook '\(ch.id)' must be registry-backed")
            XCTAssertTrue(ch.iaQueryEntry?.iaQuery.contains("collection:librivoxaudio") ?? false,
                "Audiobook '\(ch.id)' query must target the librivoxaudio collection")
        }
    }

    func testGuitarClassicalChannelInCurated() {
        // Rebuilt under a FRESH id ("guitar-classical") so it sheds stale
        // stamped tracks. Roster-driven: a curated list of MASTER guitarists
        // (whose IA catalogues are professional, all-guitar recordings),
        // INCLUDING Li Jie. The broad subject:"classical guitar" arm was dropped
        // because it flooded the channel with amateur home recordings.
        let ch = Channel.defaults.first { $0.id == "guitar-classical" }
        XCTAssertNotNil(ch, "Guitar channel must exist in Curated category")
        XCTAssertEqual(ch?.category, "Curated")
        XCTAssertEqual(ch?.name, "Classical Guitar")
        XCTAssertEqual(ch?.icon, "music.note", "icon must not be the electric 'guitars' glyph")
        // The retired ids must be gone (a fresh stamp is the whole point).
        XCTAssertNil(Channel.defaults.first { $0.id == "spanish-guitar" },
            "the old spanish-guitar channel must be removed")
        let q = ch?.iaQueryEntry?.iaQuery ?? ""
        XCTAssertTrue(q.contains("creator:\"Andrés Segovia\"")
            && q.contains("creator:\"Julian Bream\"")
            && q.contains("creator:Sabicas")
            && q.contains("creator:\"Laurindo Almeida\"")
            && q.contains("creator:\"Li Jie\""),
            "Must match the master guitarists' catalogues, including Li Jie")
        XCTAssertTrue(q.contains("Tárrega"), "must include the Tárrega repertoire arm")
        XCTAssertFalse(q.contains("creator:\"John Williams\""),
            "must NOT include John Williams (the film composer pollutes results)")
        XCTAssertTrue(q.contains("subject:vocal") && q.contains("creator:\"Salli Terri\""),
            "must exclude vocal songs (e.g. Salli Terri collaborations)")
        XCTAssertFalse(q.contains("subject:\"classical guitar\""),
            "The broad amateur-leaking subject arm must be gone")
        XCTAssertTrue(q.contains("subject:interview") && q.contains("subject:talk")
            && q.contains("subject:lecture") && q.contains("title:interview"),
            "Must still exclude interviews / talks / lectures")
        XCTAssertEqual(ch?.iaQueryEntry?.matchTags, ["guitar-classical"])
    }

    func testStringQuartetChannel() {
        let ch = Channel.defaults.first { $0.id == "string-quartet" }
        XCTAssertNotNil(ch, "String Quartet channel must exist")
        XCTAssertEqual(ch?.category, "Curated")
        XCTAssertEqual(ch?.name, "String Quartet")
        let q = ch?.iaQueryEntry?.iaQuery ?? ""
        XCTAssertTrue(q.contains("subject:\"string quartet\""),
            "must be gated to the string-quartet repertoire")
        XCTAssertTrue(q.contains("creator:Beethoven") && q.contains("creator:Haydn")
            && q.contains("creator:Shostakovich"),
            "must include the canonical quartet composers")
        XCTAssertTrue(q.contains("NOT") && q.contains("subject:guitar"),
            "must exclude non-quartet noise (e.g. guitar)")
        XCTAssertEqual(ch?.iaQueryEntry?.matchTags, ["string-quartet"])
    }

    func testReligiousMusicChannel() {
        let ch = Channel.defaults.first { $0.id == "religious-music" }
        XCTAssertNotNil(ch, "Religious Music channel must exist")
        XCTAssertEqual(ch?.category, "Curated")
        XCTAssertEqual(ch?.contentType, .music)
        let q = ch?.iaQueryEntry?.iaQuery ?? ""
        XCTAssertTrue(q.contains("subject:\"Gregorian chant\"")
            && q.contains("subject:qawwali")
            && q.contains("subject:bhajan"),
            "Religious Music must be multi-faith (chant + qawwali + bhajan)")
        XCTAssertTrue(q.contains("NOT (subject:sermon")
            || q.contains("AND NOT (subject:sermon"),
            "Religious Music must exclude sermons / lectures")
        XCTAssertTrue(q.contains("collection:audio_sermons")
            || q.contains("collection:audio_religion"),
            "Religious Music must exclude the sermon-heavy IA collections")
    }

    func testChildrensChannelsAreRegistryBackedAndSafe() {
        let books = Channel.defaults.first { $0.id == "childrens-books" }
        XCTAssertEqual(books?.category, "Curated",
            "Children's Books is a Curated channel (not just an Audiobook)")
        XCTAssertEqual(books?.contentType, .spokenWord)
        let bq = books?.iaQueryEntry?.iaQuery ?? ""
        XCTAssertTrue(bq.contains("collection:librivoxaudio"),
            "Children's Books must be LibriVox-sourced")
        XCTAssertTrue(bq.contains("audio_bookspoetry"),
            "Children's Books is broadened beyond librivoxaudio")

        let songs = Channel.defaults.first { $0.id == "childrens-songs" }
        XCTAssertEqual(songs?.category, "Curated")
        // Safety: curated IA 78rpm collection only — NOT the unsafe netlabels
        // source (profane releases), and NOT LibriVox/audiobooks (keeps it
        // MUSIC, not spoken-word).
        let q = songs?.iaQueryEntry?.iaQuery ?? ""
        XCTAssertTrue(q.contains("collection:78rpm"),
            "Children's Songs must include the curated 78rpm arm")
        XCTAssertTrue(q.contains("subject:\"kids music\""),
            "Children's Songs must include the curated kids-music tag arm")
        XCTAssertFalse(q.contains("netlabels"),
            "Children's Songs must NOT use the unsafe netlabels source")
        XCTAssertTrue(q.contains("NOT collection:librivoxaudio"),
            "Children's Songs must exclude LibriVox so it stays music, not audiobooks")
        XCTAssertTrue(q.contains("NOT title:book"),
            "Children's Songs must exclude book/audiobook items")
        XCTAssertEqual(songs?.iaQueryEntry?.matchTags, ["childrens-songs"])
    }

    // Explicit-allowlist book channels: no bulk subject:Plato/Socrates noise.
    func testCuratedBookChannelsAreExplicitAllowlists() {
        for id in ["ancient-greece", "great-books", "greater-books"] {
            let ch = Channel.defaults.first { $0.id == id }
            XCTAssertEqual(ch?.category, "Curated", "\(id) must be Curated")
            XCTAssertEqual(ch?.contentType, .spokenWord)
            let q = ch?.iaQueryEntry?.iaQuery ?? ""
            XCTAssertTrue(q.contains("collection:librivoxaudio"),
                "\(id) must be LibriVox-sourced")
            XCTAssertTrue(q.contains("creator:\""),
                "\(id) must be an explicit creator allowlist")
            XCTAssertFalse(q.lowercased().contains("subject:plato")
                || q.lowercased().contains("subject:socrates"),
                "\(id) must NOT bulk-search subject:Plato/Socrates (noise)")
            XCTAssertEqual(ch?.iaQueryEntry?.matchTags, [id])
        }
        // Ancient Greece restricts language to English/Greek.
        let ag = Channel.defaults.first { $0.id == "ancient-greece" }?
            .iaQueryEntry?.iaQuery ?? ""
        XCTAssertTrue(ag.contains("language:eng") && ag.contains("language:grc"),
            "Ancient Greece must be English/Greek only")

        // Great vs Greater are distinct, not subset-identical.
        let g  = Channel.defaults.first { $0.id == "great-books" }?
            .iaQueryEntry?.iaQuery ?? ""
        let gr = Channel.defaults.first { $0.id == "greater-books" }?
            .iaQueryEntry?.iaQuery ?? ""
        XCTAssertFalse(g.isEmpty || gr.isEmpty)
        XCTAssertNotEqual(g, gr,
            "Great Books and Greater Books must have distinct queries")
        // Great Books carries the academic canon Greater Books drops.
        XCTAssertTrue(g.contains("creator:\"Immanuel Kant\"")
            && g.contains("creator:\"Isaac Newton\""))
        XCTAssertFalse(gr.contains("creator:\"Immanuel Kant\""),
            "Greater Books is the literary list, not the science/philosophy canon")
    }

    func testCuratedChannelsAreRegistryBacked() {
        let channels = Channel.defaults.filter { $0.category == "Curated" }
        XCTAssertEqual(channels.count, 14,
            "Expected 14 Curated channels (added String Quartet; bulk Netlabels & 78 RPM dropped)")
        let ids = Set(channels.map(\.id))
        XCTAssertEqual(ids, [
            "guitar-classical", "chamber-music", "string-quartet", "historical-voices",
            "symphony-orchestra", "piano-hour", "tribal-works", "cafe-lento",
            "childrens-songs", "childrens-books",
            "ancient-greece", "great-books", "greater-books",
            "religious-music"
        ])
        // Every Curated channel must be pure-Lucene registry-backed, and its
        // matchTag stamp must equal its own id (the isolation contract).
        for ch in channels {
            guard let entry = ch.iaQueryEntry else {
                XCTFail("Curated channel '\(ch.id)' must have an ia_queries.json entry")
                continue
            }
            XCTAssertFalse(entry.iaQuery.isEmpty, "\(ch.id) iaQuery must not be empty")
            XCTAssertEqual(entry.matchTags, [ch.id],
                "\(ch.id) matchTags must be its isolation stamp [\(ch.id)]")
        }
    }

    func testFMATagChannelMatchesByTag() {
        let fmaJazz = Channel.defaults.first { $0.id == "fma-jazz" }!
        let jazzTrack  = makeTrack(composer: nil, instruments: [], tags: ["jazz"])
        let rockTrack  = makeTrack(composer: nil, instruments: [], tags: ["rock"])
        let noTagTrack = makeTrack(composer: nil, instruments: [], tags: [])
        XCTAssertTrue(fmaJazz.matches(jazzTrack),  "Jazz track should match Jazz channel")
        XCTAssertFalse(fmaJazz.matches(rockTrack), "Rock track should not match Jazz channel")
        XCTAssertFalse(fmaJazz.matches(noTagTrack),"Untagged track should not match Jazz channel")
    }

    // Regression: Soul & R&B / World Music were empty because FMA tags tracks
    // with the genre SLUG ("soul-rb") while the channel tag is "soul" —
    // Channel.matches() never matched. FMAService now stamps the channel tag.
    func testFMASlugMismatchChannelsNeedChannelTagStamp() {
        let soul = Channel.defaults.first { $0.id == "fma-soul-rnb" }!
        let world = Channel.defaults.first { $0.id == "fma-international" }!
        XCTAssertEqual(soul.tags, ["soul"])
        XCTAssertEqual(world.tags, ["world music"])

        // FMA mapTrack tags by lowercased slug — the bug.
        let slugTagged = makeTrack(composer: nil, instruments: [], tags: ["soul-rb"])
        XCTAssertFalse(soul.matches(slugTagged),
            "slug-only tag must NOT match (this was the empty-channel bug)")

        // The FMAService fix stamps the channel tag → matches.
        let stamped = slugTagged.stamped(with: ["soul"])
        XCTAssertTrue(soul.matches(stamped),
            "stamping the channel tag must make Soul & R&B match")
        let worldStamped = makeTrack(composer: nil, instruments: [], tags: ["international"])
            .stamped(with: ["world music"])
        XCTAssertTrue(world.matches(worldStamped),
            "stamping must make World Music match")
    }

    func testPreferredSourceAssignedCorrectly() {
        let spanishGuitar = Channel.defaults.first { $0.id == "guitar-classical" }!
        let fmaJazz         = Channel.defaults.first { $0.id == "fma-jazz" }!
        let oxford          = Channel.defaults.first { $0.id == "oxford-philosophy" }!

        XCTAssertEqual(spanishGuitar.preferredSource, "internet_archive")
        XCTAssertEqual(fmaJazz.preferredSource,         "fma")
        XCTAssertEqual(oxford.preferredSource,          "oxford_lectures")
    }

    // Contemporary category (formerly FMA): 14 genre channels.
    func testContemporaryCategoryHas14Channels() {
        let channels = Channel.defaults.filter { $0.category == "Contemporary" }
        XCTAssertEqual(channels.count, 14, "Expected 14 Contemporary genre channels")
    }

    func testContemporaryChannelsHaveValidTags() {
        let channels = Channel.defaults.filter { $0.category == "Contemporary" }
        for channel in channels {
            XCTAssertFalse(channel.tags.isEmpty, "Contemporary channel \(channel.id) must have at least one tag")
            let hasKnownGenre = channel.tags.first { FMAService.genreMap[$0] != nil } != nil
            XCTAssertTrue(hasKnownGenre, "Contemporary channel \(channel.id) tags must map to a known FMA genre")
        }
    }

    // Lectures category: 18 channels. music/population-health/surgical were
    // removed for returning too little podcasts.ox.ac.uk content.
    func testLecturesCategoryHas18Channels() {
        let channels = Channel.defaults.filter { $0.category == "Lectures" }
        XCTAssertEqual(channels.count, 18, "Expected 18 Lectures channels")
        let ids = Set(channels.map(\.id))
        for removed in ["oxford-music", "oxford-population-health", "oxford-surgical"] {
            XCTAssertFalse(ids.contains(removed), "\(removed) must be removed")
        }
    }

    func testLecturesChannelsAreSpokenWord() {
        let channels = Channel.defaults.filter { $0.category == "Lectures" }
        for channel in channels {
            XCTAssertEqual(channel.contentType, .spokenWord,
                "Lectures channel '\(channel.id)' must be contentType .spokenWord")
        }
    }

    func testLecturesChannelsHaveUnitSlugTag() {
        let channels = Channel.defaults.filter { $0.category == "Lectures" }
        for channel in channels {
            XCTAssertFalse(channel.tags.isEmpty,
                "Lectures channel '\(channel.id)' must have a unit slug tag for track matching")
        }
    }

    // News category: 4 channels (NPR Up First, PBS NewsHour, Democracy Now!, NPR 1A).
    // BBC*, CBC*, UN, VOA removed — broken or contain ads.
    func testNewsCategoryHas10Channels() {
        let newsChannels = Channel.defaults.filter { $0.category == "News" }
        XCTAssertEqual(newsChannels.count, 4, "Expected 4 News channels")
    }

    func testNewsChannelsHaveFeedURL() {
        let newsChannels = Channel.defaults.filter { $0.category == "News" }
        for channel in newsChannels {
            XCTAssertNotNil(channel.feedURL, "News channel '\(channel.id)' must have a feedURL")
            XCTAssertFalse(channel.feedURL?.isEmpty == true, "News channel '\(channel.id)' feedURL must not be empty")
            // tags:[id] + preferredSource:"podcast" ensure channel.matches() isolates each feed's episodes.
            XCTAssertEqual(channel.tags, [channel.id],
                "News channel '\(channel.id)' must have tags:[id] so matches() filters correctly")
            XCTAssertEqual(channel.preferredSource, "podcast",
                "News channel '\(channel.id)' must have preferredSource 'podcast' to skip IA/FMA rows")
        }
    }

    func testNewsChannelsAreSpokenWord() {
        let newsChannels = Channel.defaults.filter { $0.category == "News" }
        for channel in newsChannels {
            XCTAssertEqual(channel.contentType, .spokenWord,
                "News channel '\(channel.id)' must be contentType .spokenWord")
        }
    }

    func testChannelCodableRoundtrip() throws {
        let original = Channel.defaults[0]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.composers, original.composers)
        XCTAssertEqual(decoded.instruments, original.instruments)
    }

    // Ambient category: 4 channels (Yellowstone, Flowing Water, Rainy Day, Ocean Waves).
    // Lofi Cafe was removed.
    func testAmbientCategoryHas4Channels() {
        let channels = Channel.defaults.filter { $0.category == "Ambient" }
        XCTAssertEqual(channels.count, 4, "Expected 4 Ambient channels")
        XCTAssertFalse(channels.contains { $0.id == "ambient-lofi" },
            "Lofi Cafe must be removed")
    }

    func testYellowstoneChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "ambient-yellowstone" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.category, "Ambient")
        XCTAssertEqual(ch?.preferredSource, "nps")
        XCTAssertTrue(ch?.tags.contains("yellowstone") == true)
    }

    func testAmbientLoopChannelsHaveMatchingTags() {
        let loopChannels = Channel.defaults.filter { $0.contentType == .ambientLoop }
        XCTAssertEqual(loopChannels.count, 3, "Expected 3 ambientLoop channels")
        for channel in loopChannels {
            XCTAssertEqual(channel.tags, [channel.id],
                "AmbientLoop '\(channel.id)' must have tags:[id] so matches() isolates its single track")
            XCTAssertEqual(channel.preferredSource, "freesound",
                "AmbientLoop '\(channel.id)' must use preferredSource 'freesound'")
        }
    }

    // MARK: - Helpers

    private func makeTrack(composer: String?, instruments: [String], tags: [String] = []) -> Track {
        Track(
            id: UUID().uuidString,
            source: "internet_archive",
            title: "Test Track",
            artist: "Test Artist",
            duration: 180,
            streamURL: URL(string: "https://example.com/track.mp3")!,
            downloadURL: nil,
            localFilePath: nil,
            license: .publicDomain,
            tags: tags,
            qualityScore: 1.0,
            rawCreator: composer ?? "",
            composer: composer,
            instruments: instruments,
            metadataConfidence: 3.0
        )
    }

    // Master-menu section order (item 1): fixed sequence, only categories
    // that actually have channels, and every channel category is covered.
    func testMainMenuCategoryOrder() {
        let order = MainMenuView.orderedCategories()
        XCTAssertEqual(order, ["Curated", "Ambient", "News", "Contemporary",
                               "Audiobooks", "Lectures"])
        // No channel category is silently dropped from the menu.
        let present = Set(Channel.defaults.map(\.category))
        XCTAssertEqual(Set(order), present,
            "every channel category must appear in the menu order")
    }
}
