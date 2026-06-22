import XCTest
@testable import ParsoMusic

final class MediaKindTests: XCTestCase {

    // MARK: - MediaKind classification per channel

    func testForYouChannelsAreMusic() {
        XCTAssertEqual(Channel.defaults.first(where: { $0.id == "music-for-you" })?.mediaKind, .music)
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
            "news-democracy-now", "podcast-no-agenda", "podcast-citations-needed",
            "podcast-security-now", "podcast-floss-weekly"
        ]
        for id in podcastIDs {
            guard let channel = Channel.defaults.first(where: { $0.id == id }) else {
                XCTFail("Channel \(id) not found in defaults")
                continue
            }
            XCTAssertEqual(channel.mediaKind, .podcast, "\(channel.id) should be .podcast, got \(channel.mediaKind)")
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
        XCTAssertTrue(b.supportsSleepTimer)
        XCTAssertFalse(b.persistsResumePosition)
        XCTAssertFalse(b.supportsBookSkip)
        XCTAssertFalse(b.supportsBookmarks)
        XCTAssertFalse(b.startsAtZeroAlways)
        XCTAssertTrue(b.supportsTransportNavigation)
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
        XCTAssertTrue(b.supportsTransportNavigation)
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
        XCTAssertTrue(b.supportsTransportNavigation)
    }

    func testLectureBehavior() {
        let b = MediaKind.lecture.behavior
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
        XCTAssertTrue(b.supportsTransportNavigation)
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
        XCTAssertFalse(b.supportsTransportNavigation)
    }

    func testMusicSupportsSleepTimer() {
        XCTAssertTrue(MediaKind.music.behavior.supportsSleepTimer,
            "Music should support sleep timer")
    }

    func testTransportNavigationDisabledForAmbientOnly() {
        XCTAssertTrue(MediaKind.music.behavior.supportsTransportNavigation)
        XCTAssertTrue(MediaKind.audiobook.behavior.supportsTransportNavigation)
        XCTAssertTrue(MediaKind.podcast.behavior.supportsTransportNavigation)
        XCTAssertTrue(MediaKind.lecture.behavior.supportsTransportNavigation)
        XCTAssertFalse(MediaKind.ambient.behavior.supportsTransportNavigation)
    }

    // MARK: - Behavior aligns with Phase 0 baseline

    func testShuffleBehaviorAlignsWithBaseline() {
        for channel in Channel.defaults {
            let expectedShuffle = QueueManager.usesShuffle(channel: channel, shuffleMode: false)
            let behaviorShuffles = channel.behavior.queueStyle == .shuffledPool
            let isRadio = channel.iaQueryEntry != nil
            if isRadio {
                XCTAssertTrue(behaviorShuffles || expectedShuffle,
                    "\(channel.id): radio channel should shuffle")
            }
        }
    }

    func testProgressBarAlignsWithBaseline() {
        for channel in Channel.defaults {
            let expectedProgressBar = channel.contentType == .spokenWord
            let behaviorProgressBar = channel.behavior.showsScrubbableProgress
            if expectedProgressBar {
                XCTAssertTrue(behaviorProgressBar,
                    "\(channel.id): spokenWord channel should show scrubbable progress")
            } else {
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
                if channel.category == "Podcasts" || channel.category == "Lectures"
                    || channel.category == "Audiobooks"
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

    func testTrackMediaKindForSpokenWordMultiPart() {
        let channel = Channel(id: "test", name: "Test", category: "Lectures", icon: "book",
                              contentType: .spokenWord, preferredSource: "internet_archive")
        let track = makeTestTrack(id: "sw-1", source: "internet_archive",
                                  parentId: "some-parent")
        XCTAssertEqual(track.mediaKind(in: channel), .audiobook)
    }

    func testTrackMediaKindForMusicDefault() {
        let channel = Channel(id: "test-music", name: "Test Music", category: "Curated",
                              icon: "music.note", tags: ["test"], preferredSource: "internet_archive")
        let track = makeTestTrack(id: "music-1", source: "internet_archive")
        XCTAssertEqual(track.mediaKind(in: channel), .music)
    }

    // MARK: - LibrarySection ordering

    func testLibrarySectionOrderLecturesBeforePodcasts() {
        let ordered = LibrarySection.ordered.map(\.id)
        guard let lecturesIdx = ordered.firstIndex(of: .lecture),
              let podcastsIdx = ordered.firstIndex(of: .podcast) else {
            XCTFail("Expected both .lecture and .podcast in ordered sections")
            return
        }
        XCTAssertLessThan(lecturesIdx, podcastsIdx,
            "Lectures should appear before Podcasts in Explore")
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
