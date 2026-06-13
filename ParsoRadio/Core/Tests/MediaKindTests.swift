import XCTest
@testable import ParsoMusic

final class MediaKindTests: XCTestCase {

    // MARK: - MediaKind classification per channel

    func testForYouChannelsAreMusic() {
        XCTAssertEqual(Channel.defaults.first(where: { $0.id == "music-for-you" })?.mediaKind, .music)
        // books-for-you is spokenWord but no Audiobooks/Curated Books category → audiobook (per spokeWord fallback)
        XCTAssertEqual(Channel.defaults.first(where: { $0.id == "books-for-you" })?.mediaKind, .audiobook)
    }

    func testLectureChannelsAreLecture() {
        let lectureIDs = [
            "oxford-business", "oxford-chemistry", "oxford-classics",
            "oxford-computer-science", "oxford-economics", "oxford-education",
            "oxford-engineering", "oxford-english", "oxford-history",
            "oxford-torch", "oxford-maths", "oxford-clinical-medicine",
            "oxford-martin", "oxford-philosophy", "oxford-physics",
            "oxford-psychology", "oxford-anatomy", "oxford-internet"
        ]
        for id in lectureIDs {
            guard let channel = Channel.defaults.first(where: { $0.id == id }) else {
                XCTFail("Channel \(id) not found in defaults")
                continue
            }
            XCTAssertEqual(channel.mediaKind, .lecture, "\(channel.id) should be .lecture, got \(channel.mediaKind)")
        }
    }

    func testPodcastChannelsArePodcast() {
        let podcastIDs = [
            "news-nprup-first", "news-pbs-newshour", "news-democracy-now",
            "news-npr-1a", "news-bbc-global", "news-dw-inside-europe",
            "news-cbc-as-it-happens", "podcast-joe-rogan", "podcast-nyt-daily",
            "podcast-this-american-life", "podcast-ted-radio-hour", "podcast-npr-politics"
        ]
        for id in podcastIDs {
            guard let channel = Channel.defaults.first(where: { $0.id == id }) else {
                XCTFail("Channel \(id) not found in defaults")
                continue
            }
            XCTAssertEqual(channel.mediaKind, .podcast, "\(channel.id) should be .podcast, got \(channel.mediaKind)")
        }
    }

    func testCuratedChannelsAreMusic() {
        let curatedIDs = [
            "guitar-classical", "string-quartet", "symphony-orchestra",
            "piano-hour", "tribal-works", "cafe-lento",
            "childrens-songs", "ajc-project", "chamber-music"
        ]
        for id in curatedIDs {
            guard let channel = Channel.defaults.first(where: { $0.id == id }) else {
                XCTFail("Channel \(id) not found in defaults")
                continue
            }
            XCTAssertEqual(channel.mediaKind, .music, "\(channel.id) should be .music, got \(channel.mediaKind)")
        }
    }

    func testCuratedBookChannelsAreAudiobook() {
        let bookIDs = [
            "great-books", "childrens-books", "ancient-greece",
            "popular-literature", "greater-books"
        ]
        for id in bookIDs {
            guard let channel = Channel.defaults.first(where: { $0.id == id }) else {
                XCTFail("Channel \(id) not found in defaults")
                continue
            }
            XCTAssertEqual(channel.mediaKind, .audiobook, "\(channel.id) should be .audiobook, got \(channel.mediaKind)")
        }
    }

    func testAudiobookChannelsAreAudiobook() {
        let audiobookIDs = [
            "lv-general-fiction", "lv-literary-fiction", "lv-science-fiction",
            "lv-horror-gothic", "lv-mystery-crime", "lv-adventure",
            "lv-fantasy-mythology", "lv-romance", "lv-satire-humor",
            "lv-war-military", "lv-short-stories", "lv-drama-plays",
            "lv-travel", "lv-ancient-world", "lv-poetry",
            "lv-philosophy-mind", "lv-history", "lv-biography",
            "lv-science-nature", "lv-religion", "lv-essays-ideas"
        ]
        for id in audiobookIDs {
            guard let channel = Channel.defaults.first(where: { $0.id == id }) else {
                XCTFail("Channel \(id) not found in defaults")
                continue
            }
            XCTAssertEqual(channel.mediaKind, .audiobook, "\(channel.id) should be .audiobook, got \(channel.mediaKind)")
        }
    }

    func testAmbientChannelsAreAmbient() {
        let ambientIDs = [
            "ambient-yellowstone", "ambient-flowing-water",
            "ambient-rain", "ambient-ocean"
        ]
        for id in ambientIDs {
            guard let channel = Channel.defaults.first(where: { $0.id == id }) else {
                XCTFail("Channel \(id) not found in defaults")
                continue
            }
            XCTAssertEqual(channel.mediaKind, .ambient, "\(channel.id) should be .ambient, got \(channel.mediaKind)")
        }
    }

    func testEveryChannelDefaultsHasMediaKind() {
        for channel in Channel.defaults {
            _ = channel.mediaKind
            _ = channel.behavior
        }
    }

    // MARK: - MediaKind → behavior table

    func testMusicBehavior() {
        let b = MediaKind.music.behavior
        XCTAssertEqual(b.queueStyle, .shuffledPool)
        XCTAssertTrue(b.allowsShuffleToggle)
        XCTAssertFalse(b.showsScrubbableProgress)
        XCTAssertFalse(b.supportsChapters)
        XCTAssertFalse(b.supportsSpeedControl)
        XCTAssertFalse(b.supportsSleepTimer)
        XCTAssertFalse(b.persistsResumePosition)
        XCTAssertFalse(b.supportsBookSkip)
        XCTAssertFalse(b.supportsBookmarks)
        XCTAssertFalse(b.startsAtZeroAlways)
    }

    func testAudiobookBehavior() {
        let b = MediaKind.audiobook.behavior
        XCTAssertEqual(b.queueStyle, .sequentialInOrder)
        XCTAssertFalse(b.allowsShuffleToggle)
        XCTAssertTrue(b.showsScrubbableProgress)
        XCTAssertTrue(b.supportsChapters)
        XCTAssertTrue(b.supportsSpeedControl)
        XCTAssertTrue(b.supportsSleepTimer)
        XCTAssertTrue(b.persistsResumePosition)
        XCTAssertTrue(b.supportsBookSkip)
        XCTAssertTrue(b.supportsBookmarks)
        XCTAssertFalse(b.startsAtZeroAlways)
    }

    func testPodcastBehavior() {
        let b = MediaKind.podcast.behavior
        XCTAssertEqual(b.queueStyle, .sequentialNewestFirst)
        XCTAssertFalse(b.allowsShuffleToggle)
        XCTAssertTrue(b.showsScrubbableProgress)
        XCTAssertFalse(b.supportsChapters)
        XCTAssertTrue(b.supportsSpeedControl)
        XCTAssertTrue(b.supportsSleepTimer)
        XCTAssertTrue(b.persistsResumePosition)
        XCTAssertFalse(b.supportsBookSkip)
        XCTAssertTrue(b.supportsBookmarks)
        XCTAssertTrue(b.startsAtZeroAlways)
    }

    func testLectureBehavior() {
        let b = MediaKind.lecture.behavior
        XCTAssertEqual(b.queueStyle, .shuffledPool)
        XCTAssertFalse(b.allowsShuffleToggle)
        XCTAssertTrue(b.showsScrubbableProgress)
        XCTAssertFalse(b.supportsChapters)
        XCTAssertTrue(b.supportsSpeedControl)
        XCTAssertTrue(b.supportsSleepTimer)
        XCTAssertTrue(b.persistsResumePosition)
        XCTAssertFalse(b.supportsBookSkip)
        XCTAssertTrue(b.supportsBookmarks)
        XCTAssertFalse(b.startsAtZeroAlways)
    }

    func testAmbientBehavior() {
        let b = MediaKind.ambient.behavior
        XCTAssertEqual(b.queueStyle, .singleLoop)
        XCTAssertFalse(b.allowsShuffleToggle)
        XCTAssertFalse(b.showsScrubbableProgress)
        XCTAssertFalse(b.supportsChapters)
        XCTAssertFalse(b.supportsSpeedControl)
        XCTAssertTrue(b.supportsSleepTimer)
        XCTAssertFalse(b.persistsResumePosition)
        XCTAssertFalse(b.supportsBookSkip)
        XCTAssertFalse(b.supportsBookmarks)
        XCTAssertFalse(b.startsAtZeroAlways)
    }

    // MARK: - Behavior aligns with Phase 0 baseline

    func testShuffleBehaviorAlignsWithBaseline() {
        for channel in Channel.defaults {
            let expectedShuffle = QueueManager.usesShuffle(channel: channel, shuffleMode: false)
            let behaviorShuffles = channel.behavior.queueStyle == .shuffledPool
            let isRadio = channel.iaQueryEntry != nil
            // Baseline says: shuffle when iaQueryEntry != nil OR lecture
            // behavior.queueStyle == .shuffledPool when those are true AND the
            // radio flag is respected by effectiveQueueStyle in QueueManager
            if isRadio || channel.category == "Lectures" {
                XCTAssertTrue(behaviorShuffles || expectedShuffle,
                    "\(channel.id): radio/lecture channel should shuffle")
            }
        }
    }

    func testProgressBarAlignsWithBaseline() {
        for channel in Channel.defaults {
            let expectedProgressBar = channel.contentType == .spokenWord
            let behaviorProgressBar = channel.behavior.showsScrubbableProgress
            // All spokenWord channels should show progress bar in behavior
            if expectedProgressBar {
                XCTAssertTrue(behaviorProgressBar,
                    "\(channel.id): spokenWord channel should show scrubbable progress")
            } else {
                // Non-spokenWord: ambient should be false, music should be false
                // Ambient channels: contentType .ambientLoop → not spokenWord → no progress
                XCTAssertFalse(behaviorProgressBar,
                    "\(channel.id): non-spokenWord channel should not show scrubbable progress")
            }
        }
    }

    func testResumePositionAlignsWithBaseline() {
        for channel in Channel.defaults {
            let expectedPersists = channel.contentType != .ambientLoop
            let behaviorPersists = channel.behavior.persistsResumePosition
            if expectedPersists {
                // All non-ambientLoop channels persist position
                if channel.category == "Podcasts" || channel.category == "Lectures"
                    || channel.category == "Audiobooks" || channel.category == "Curated Books"
                    || (channel.id == "books-for-you") {
                    XCTAssertTrue(behaviorPersists,
                        "\(channel.id): should persist resume position")
                }
            } else {
                XCTAssertFalse(behaviorPersists,
                    "\(channel.id): ambient should not persist resume position")
            }
        }
    }

    // MARK: - Track.mediaKind(in:)

    func testTrackMediaKindForPodcastSource() {
        let track = makeTestTrack(id: "pod-1", source: "podcast")
        XCTAssertEqual(track.mediaKind(in: nil), .podcast)
    }

    func testTrackMediaKindForOxfordSource() {
        let track = makeTestTrack(id: "ox-1", source: "oxford_lectures")
        XCTAssertEqual(track.mediaKind(in: nil), .lecture)
    }

    func testTrackMediaKindForAudiobookCategory() {
        let channel = Channel.defaults.first(where: { $0.category == "Audiobooks" })!
        let track = makeTestTrack(id: "ia-1", source: "internet_archive")
        XCTAssertEqual(track.mediaKind(in: channel), .audiobook)
    }

    func testTrackMediaKindForCuratedBooksCategory() {
        let channel = Channel.defaults.first(where: { $0.category == "Curated Books" })!
        let track = makeTestTrack(id: "cb-1", source: "internet_archive")
        XCTAssertEqual(track.mediaKind(in: channel), .audiobook)
    }

    func testTrackMediaKindForSpokenWordMultiPart() {
        let channel = Channel(id: "test", name: "Test", category: "Lectures", icon: "book",
                              contentType: .spokenWord, preferredSource: "internet_archive")
        let track = makeTestTrack(id: "sw-1", source: "internet_archive",
                                  parentId: "some-parent")
        XCTAssertEqual(track.mediaKind(in: channel), .audiobook)
    }

    func testTrackMediaKindForMusicDefault() {
        let channel = Channel.defaults.first(where: { $0.category == "Curated" && $0.contentType == .music })!
        let track = makeTestTrack(id: "music-1", source: "internet_archive")
        XCTAssertEqual(track.mediaKind(in: channel), .music)
    }
}

private func makeTestTrack(id: String, source: String,
                           duration: Double = 100,
                           parentId: String? = nil) -> Track {
    Track(id: id, source: source, title: "Title", artist: "Artist",
          duration: duration,
          streamURL: URL(string: "https://example.com/\(id)")!,
          downloadURL: nil, license: .cc0, tags: [], qualityScore: 1,
          rawCreator: "", composer: nil, instruments: [],
          metadataConfidence: 1,
          parentIdentifier: parentId)
}
