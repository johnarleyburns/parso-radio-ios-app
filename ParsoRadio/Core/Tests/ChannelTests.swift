import XCTest
@testable import ParsoMusic

final class ChannelTests: XCTestCase {

    func testDefaultChannelCount() {
        // 25 Classical + 22 Audiobooks + 14 Contemporary + 21 Lectures + 4 News + 5 Ambient + 2 Curated = 93
        XCTAssertEqual(Channel.defaults.count, 93)
    }

    func testClassicalCategoryHas25Channels() {
        let classicalChannels = Channel.defaults.filter { $0.category == "Classical" }
        // chamber-music moved to Curated (pure-Lucene), so 7 period/format/instrument
        // + 18 composer channels remain.
        XCTAssertEqual(classicalChannels.count, 25,
            "Classical: 7 period/format/instrument + 18 composer channels")
    }

    func testSpanishGuitarChannelInCurated() {
        let ch = Channel.defaults.first { $0.id == "spanish-guitar" }
        XCTAssertNotNil(ch, "Spanish Guitar channel must exist in Curated category")
        XCTAssertEqual(ch?.category, "Curated")
        // Pure-Lucene: curation lives entirely in the ia_queries.json query,
        // not in excludeTags. The channel must be registry-backed instead.
        XCTAssertNotNil(ch?.iaQueryEntry, "Spanish Guitar must be registry-backed (pure-Lucene)")
    }

    func testCuratedCategoryHas2Channels() {
        let channels = Channel.defaults.filter { $0.category == "Curated" }
        XCTAssertEqual(channels.count, 2,
            "Expected 2 Curated channels (Spanish Guitar, Chamber Music)")
        // Every Curated channel must be pure-Lucene registry-backed.
        for ch in channels {
            XCTAssertNotNil(ch.iaQueryEntry,
                "Curated channel '\(ch.id)' must have an ia_queries.json entry")
        }
    }

    func testBachChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "bach" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.composers, ["bach"])
        XCTAssertEqual(ch?.category, "Classical")
        XCTAssertEqual(ch?.preferredSource, "internet_archive")
    }

    func testMozartChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "mozart" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.composers, ["mozart"])
        XCTAssertEqual(ch?.category, "Classical")
    }

    func testClassicalGuitarChannelExists() {
        let ch = Channel.defaults.first { $0.id == "classical-guitar" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.category, "Classical")
        XCTAssertTrue(ch?.tags.contains("classical guitar") == true)
    }

    func testCelloChannelExists() {
        let ch = Channel.defaults.first { $0.id == "cello" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.category, "Classical")
        XCTAssertTrue(ch?.tags.contains("cello") == true)
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

    func testPreferredSourceAssignedCorrectly() {
        let bach         = Channel.defaults.first { $0.id == "bach" }!
        let fmaJazz      = Channel.defaults.first { $0.id == "fma-jazz" }!
        let greekPhilo   = Channel.defaults.first { $0.id == "greek-philosophy" }!
        let oxford       = Channel.defaults.first { $0.id == "oxford-philosophy" }!

        XCTAssertEqual(bach.preferredSource,       "internet_archive")
        XCTAssertEqual(fmaJazz.preferredSource,    "fma")
        XCTAssertEqual(greekPhilo.preferredSource, "internet_archive")
        XCTAssertEqual(oxford.preferredSource,     "oxford_lectures")
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

    func testAudiobooksCategoryHas22Channels() {
        let lvChannels = Channel.defaults.filter { $0.category == "Audiobooks" }
        XCTAssertEqual(lvChannels.count, 22,
            "Expected 4 named + 18 genre Audiobooks channels")
    }

    // Non-feed spoken-word channels (not Lectures or News) must use "Audiobooks" category.
    func testNonFeedSpokenWordChannelsUseAudiobooksCategory() {
        let librivoxChannels = Channel.defaults.filter {
            $0.contentType == .spokenWord
                && $0.category != "Lectures"
                && $0.category != "News"
        }
        XCTAssertFalse(librivoxChannels.isEmpty, "Expected at least one Audiobooks spoken-word channel")
        for channel in librivoxChannels {
            XCTAssertEqual(channel.category, "Audiobooks",
                "Spoken-word channel '\(channel.id)' must use 'Audiobooks' category")
        }
    }

    // Lectures category: 21 channels (Blavatnik removed — 0 series on podcasts.ox.ac.uk).
    func testLecturesCategoryHas22Channels() {
        let channels = Channel.defaults.filter { $0.category == "Lectures" }
        XCTAssertEqual(channels.count, 21, "Expected 21 Lectures channels")
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

    // Ambient category: 5 channels (Yellowstone, Lofi Cafe, Flowing Water, Rainy Day, Ocean Waves).
    func testAmbientCategoryHas5Channels() {
        let channels = Channel.defaults.filter { $0.category == "Ambient" }
        XCTAssertEqual(channels.count, 5, "Expected 5 Ambient channels")
    }

    func testYellowstoneChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "ambient-yellowstone" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.category, "Ambient")
        XCTAssertEqual(ch?.preferredSource, "nps")
        XCTAssertTrue(ch?.tags.contains("yellowstone") == true)
    }

    func testLofiCafeChannelDefinition() {
        let ch = Channel.defaults.first { $0.id == "ambient-lofi" }
        XCTAssertNotNil(ch)
        XCTAssertEqual(ch?.category, "Ambient")
        XCTAssertEqual(ch?.preferredSource, "fma")
        XCTAssertTrue(ch?.tags.contains("lo-fi-hip-hop") == true,
            "Lofi Cafe tag must match FMAService.genreMap key 'lo-fi-hip-hop'")
        XCTAssertNotNil(FMAService.genreMap["lo-fi-hip-hop"],
            "FMAService.genreMap must contain 'lo-fi-hip-hop' for Lofi Cafe to fetch")
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
