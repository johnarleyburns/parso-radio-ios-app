import XCTest
@testable import ParsoMusic

final class ChannelTests: XCTestCase {

    func testDefaultChannelCount() {
        // 14 Contemporary + 18 Lectures + 4 News + 4 Ambient + 10 Curated
        // + 21 Audiobooks (LibriVox) = 71.
        XCTAssertEqual(Channel.defaults.count, 71)
    }

    func testEveryIAChannelIsPureLuceneRegistryBacked() {
        // Legacy Classical is gone. Audiobooks are back, but ONLY as
        // pure-Lucene registry channels — every internet_archive channel
        // (Curated music + LibriVox audiobooks) must have an ia_queries.json
        // entry whose stamp is its own id. No code-side filtered IA channels.
        XCTAssertTrue(Channel.defaults.allSatisfy { $0.category != "Classical" },
            "No legacy Classical channels should remain")
        for ch in Channel.defaults where ch.preferredSource == "internet_archive" {
            XCTAssertTrue(ch.category == "Curated" || ch.category == "Audiobooks",
                "IA channel '\(ch.id)' must be Curated or Audiobooks")
            guard let entry = ch.iaQueryEntry else {
                XCTFail("IA channel '\(ch.id)' must be registry-backed"); continue
            }
            XCTAssertEqual(entry.matchTags, [ch.id],
                "IA channel '\(ch.id)' stamp must be [\(ch.id)]")
        }
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

    func testSpanishGuitarChannelInCurated() {
        let ch = Channel.defaults.first { $0.id == "spanish-guitar" }
        XCTAssertNotNil(ch, "Spanish Guitar channel must exist in Curated category")
        XCTAssertEqual(ch?.category, "Curated")
        XCTAssertNotNil(ch?.iaQueryEntry, "Spanish Guitar must be registry-backed (pure-Lucene)")
    }

    func testCuratedChannelsAreRegistryBacked() {
        let channels = Channel.defaults.filter { $0.category == "Curated" }
        XCTAssertEqual(channels.count, 10,
            "Expected 10 Curated channels")
        let ids = Set(channels.map(\.id))
        XCTAssertEqual(ids, [
            "spanish-guitar", "chamber-music", "historical-voices",
            "symphony-orchestra", "piano-hour", "tribal-works", "cafe-lento",
            "netlabels", "lofi", "rpm-78"
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
        let spanishGuitar = Channel.defaults.first { $0.id == "spanish-guitar" }!
        let fmaJazz       = Channel.defaults.first { $0.id == "fma-jazz" }!
        let oxford        = Channel.defaults.first { $0.id == "oxford-philosophy" }!

        XCTAssertEqual(spanishGuitar.preferredSource, "internet_archive")
        XCTAssertEqual(fmaJazz.preferredSource,       "fma")
        XCTAssertEqual(oxford.preferredSource,        "oxford_lectures")
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
}
