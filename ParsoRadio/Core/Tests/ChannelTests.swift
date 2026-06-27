import XCTest
@testable import ParsoMusic

final class ChannelTests: XCTestCase {

    func testDefaultChannelCount() {
        // 3 For You + 18 Lectures + 32 Podcasts + 4 Ambient
        // + 21 Audiobooks (LibriVox) = 78.
        XCTAssertEqual(Channel.defaults.count, 78)
    }

    func testEveryIAChannelIsPureLuceneRegistryBacked() {
        XCTAssertTrue(Channel.defaults.allSatisfy { $0.category != "Classical" },
            "No legacy Classical channels should remain")
        for ch in Channel.defaults where ch.preferredSource == "internet_archive"
            && ch.category != "For You" {
            XCTAssertEqual(ch.category, "Audiobooks",
                "IA channel '\(ch.id)' in defaults must be Audiobooks")
            guard let entry = ch.iaQueryEntry else {
                XCTFail("IA channel '\(ch.id)' must be registry-backed"); continue
            }
            XCTAssertEqual(entry.matchTags, [ch.id],
                "IA channel '\(ch.id)' stamp must be [\(ch.id)]")
        }
    }

    func testForYouChannelsExistAndAreDynamic() {
        let ids = Set(Channel.defaults.filter { $0.category == "For You" }.map(\.id))
        XCTAssertEqual(ids, ["books-for-you", "for-you", "music-for-you"])
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

    func testPreferredSourceAssignedCorrectly() {
        let audiobook = Channel.defaults.first { $0.id == "lv-general-fiction" }!
        let oxford    = Channel.defaults.first { $0.id == "oxford-philosophy" }!

        XCTAssertEqual(audiobook.preferredSource, "internet_archive")
        XCTAssertEqual(oxford.preferredSource,    "oxford_lectures")
    }

    func testNoContemporaryOrFMAChannelsRemain() {
        XCTAssertTrue(Channel.defaults.allSatisfy { $0.category != "Contemporary" },
            "Contemporary category must be empty after the wedge pivot")
        XCTAssertTrue(Channel.defaults.allSatisfy { $0.preferredSource != "fma" },
            "No channel should source from FMA after the wedge pivot")
    }

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

    func testPodcastsCategoryHasExpectedChannels() {
        let newsChannels = Channel.defaults.filter { $0.category == "Podcasts" }
        XCTAssertEqual(newsChannels.count, 32, "Expected 32 Podcasts channels")
    }

    func testPodcastsChannelsHaveFeedURL() {
        let newsChannels = Channel.defaults.filter { $0.category == "Podcasts" }
        for channel in newsChannels {
            XCTAssertNotNil(channel.feedURL, "Podcasts channel '\(channel.id)' must have a feedURL")
            XCTAssertFalse(channel.feedURL?.isEmpty == true, "Podcasts channel '\(channel.id)' feedURL must not be empty")
            XCTAssertEqual(channel.tags, [channel.id],
                "Podcasts channel '\(channel.id)' must have tags:[id] so matches() filters correctly")
            XCTAssertEqual(channel.preferredSource, "podcast",
                "Podcasts channel '\(channel.id)' must have preferredSource 'podcast' to skip IA/FMA rows")
        }
    }

    func testPodcastsChannelsAreSpokenWord() {
        let newsChannels = Channel.defaults.filter { $0.category == "Podcasts" }
        for channel in newsChannels {
            XCTAssertEqual(channel.contentType, .spokenWord,
                "Podcasts channel '\(channel.id)' must be contentType .spokenWord")
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

    func testNoCuratedOrCuratedBooksInDefaults() {
        XCTAssertTrue(Channel.defaults.allSatisfy { $0.category != "Curated" },
            "Curated category must not exist in defaults (removed)")
        XCTAssertTrue(Channel.defaults.allSatisfy { $0.category != "Curated Books" },
            "Curated Books category must not exist in defaults (removed)")
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

    func testMainMenuCategoryOrder() {
        let categoryOrder = ["Ambient", "Podcasts", "Audiobooks", "Lectures"]
        let present = Set(Channel.defaults.map(\.category))
        let order = categoryOrder.filter(present.contains)
        XCTAssertEqual(order, categoryOrder)
        XCTAssertFalse(order.contains("For You"),
            "For You channels live inside Playlists, not the top-level menu")
        for cat in order {
            XCTAssertTrue(present.contains(cat),
                "menu order lists \(cat) but no channel has that category")
        }
    }
}
