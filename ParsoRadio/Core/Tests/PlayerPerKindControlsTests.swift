import XCTest
@testable import ParsoMusic

@MainActor
final class PlayerPerKindControlsTests: XCTestCase {

    // MARK: - Music behavior

    func testMusicBehaviorFlags() {
        let behavior = MediaKind.music.behavior
        XCTAssertTrue(behavior.allowsShuffleToggle)
        XCTAssertFalse(behavior.showsScrubbableProgress)
        XCTAssertFalse(behavior.supportsChapters)
        XCTAssertFalse(behavior.supportsSpeedControl)
        XCTAssertTrue(behavior.supportsSleepTimer)
        XCTAssertFalse(behavior.supportsBookSkip)
        XCTAssertFalse(behavior.supportsBookmarks)
        XCTAssertTrue(behavior.supportsTransportNavigation)
        XCTAssertEqual(behavior.queueStyle, .shuffledPool)
    }

    // Music: has track skip, no jog
    func testMusicUsesTrackSkipNotJog() {
        let behavior = MediaKind.music.behavior
        XCTAssertFalse(behavior.showsScrubbableProgress)
        XCTAssertTrue(behavior.supportsTransportNavigation)
        // Music has no scrub → jog buttons are not applicable
        // Track navigation is via backward.fill/forward.fill
    }

    // MARK: - Audiobook behavior

    func testAudiobookBehaviorFlags() {
        let behavior = MediaKind.audiobook.behavior
        XCTAssertFalse(behavior.allowsShuffleToggle)
        XCTAssertTrue(behavior.showsScrubbableProgress)
        XCTAssertTrue(behavior.supportsChapters)
        XCTAssertTrue(behavior.supportsSpeedControl)
        XCTAssertTrue(behavior.supportsSleepTimer)
        XCTAssertTrue(behavior.supportsBookSkip)
        XCTAssertTrue(behavior.supportsBookmarks)
        XCTAssertTrue(behavior.supportsTransportNavigation)
        XCTAssertEqual(behavior.queueStyle, .sequentialInOrder)
    }

    // Audiobook: has jog, no track skip on surface
    func testAudiobookUsesJogNotTrackSkip() {
        let behavior = MediaKind.audiobook.behavior
        XCTAssertTrue(behavior.showsScrubbableProgress)
        // Audiobook shows scrub + jog; track step is NOT on the surface
        // Book skip lives in overflow
        XCTAssertTrue(behavior.supportsBookSkip)
    }

    // MARK: - Lecture behavior

    func testLectureBehaviorFlags() {
        let behavior = MediaKind.lecture.behavior
        XCTAssertFalse(behavior.allowsShuffleToggle)
        XCTAssertTrue(behavior.showsScrubbableProgress)
        XCTAssertTrue(behavior.supportsChapters)
        XCTAssertTrue(behavior.supportsSpeedControl)
        XCTAssertTrue(behavior.supportsSleepTimer)
        XCTAssertTrue(behavior.supportsBookSkip)
        XCTAssertTrue(behavior.supportsBookmarks)
        XCTAssertTrue(behavior.supportsTransportNavigation)
        XCTAssertEqual(behavior.queueStyle, .sequentialInOrder)
    }

    // Lecture shares SpokenControls with audiobook — same layout, different labels
    func testLectureSameLayoutAsAudiobook() {
        let audiobook = MediaKind.audiobook.behavior
        let lecture = MediaKind.lecture.behavior
        XCTAssertEqual(audiobook.showsScrubbableProgress, lecture.showsScrubbableProgress)
        XCTAssertEqual(audiobook.supportsChapters, lecture.supportsChapters)
        XCTAssertEqual(audiobook.supportsSpeedControl, lecture.supportsSpeedControl)
        XCTAssertEqual(audiobook.supportsBookSkip, lecture.supportsBookSkip)
        XCTAssertEqual(audiobook.supportsBookmarks, lecture.supportsBookmarks)
    }

    // MARK: - Podcast behavior

    func testPodcastBehaviorFlags() {
        let behavior = MediaKind.podcast.behavior
        XCTAssertFalse(behavior.allowsShuffleToggle)
        XCTAssertTrue(behavior.showsScrubbableProgress)
        XCTAssertFalse(behavior.supportsChapters)
        XCTAssertTrue(behavior.supportsSpeedControl)
        XCTAssertTrue(behavior.supportsSleepTimer)
        XCTAssertFalse(behavior.supportsBookSkip)
        XCTAssertTrue(behavior.supportsBookmarks)
        XCTAssertTrue(behavior.supportsTransportNavigation)
        XCTAssertEqual(behavior.queueStyle, .sequentialNewestFirst)
    }

    // Podcast: has jog, no chapters
    func testPodcastHasJogNoChapters() {
        let behavior = MediaKind.podcast.behavior
        XCTAssertTrue(behavior.showsScrubbableProgress)
        XCTAssertFalse(behavior.supportsChapters)
    }

    // MARK: - Ambient behavior

    func testAmbientBehaviorFlags() {
        let behavior = MediaKind.ambient.behavior
        XCTAssertFalse(behavior.allowsShuffleToggle)
        XCTAssertFalse(behavior.showsScrubbableProgress)
        XCTAssertFalse(behavior.supportsChapters)
        XCTAssertFalse(behavior.supportsSpeedControl)
        XCTAssertTrue(behavior.supportsSleepTimer)
        XCTAssertFalse(behavior.supportsBookSkip)
        XCTAssertFalse(behavior.supportsBookmarks)
        XCTAssertFalse(behavior.supportsTransportNavigation)
        XCTAssertEqual(behavior.queueStyle, .singleLoop)
    }

    // Ambient: bookmark support is now false
    func testAmbientDoesNotSupportBookmarks() {
        XCTAssertFalse(MediaKind.ambient.behavior.supportsBookmarks)
    }

    // Ambient: no scrub, no jog, no skip
    func testAmbientHasNoScrubNoJogNoSkip() {
        let behavior = MediaKind.ambient.behavior
        XCTAssertFalse(behavior.showsScrubbableProgress)
        XCTAssertFalse(behavior.supportsTransportNavigation)
        XCTAssertFalse(behavior.supportsBookSkip)
    }

    // MARK: - Scope grammar: disambiguation

    func testNoKindShowsBothJogAndTrackSkipBehavior() {
        // Music: showsScrubbableProgress=false (no jog) + supportsTransportNavigation=true (track skip)
        // Audiobook/Lecture/Podcast: showsScrubbableProgress=true (jog) + supportsTransportNavigation=true
        //   BUT the design rule says track skip is NOT on surface for these kinds
        // Ambient: showsScrubbableProgress=false + supportsTransportNavigation=false
        //
        // The scope grammar is enforced at the View layer, not the Behavior model.
        // The Behavior model provides the *capabilities*; the per-kind views decide placement.
        // This test verifies the model is correct for the views to enforce.

        // Music: can skip tracks, cannot scrub (no jog)
        let music = MediaKind.music.behavior
        XCTAssertFalse(music.showsScrubbableProgress)

        // Audiobook: can scrub (jog surface), book skip is capability but goes to overflow
        let audiobook = MediaKind.audiobook.behavior
        XCTAssertTrue(audiobook.showsScrubbableProgress)

        // Podcast: can scrub (jog surface), no book skip at all
        let podcast = MediaKind.podcast.behavior
        XCTAssertTrue(podcast.showsScrubbableProgress)
        XCTAssertFalse(podcast.supportsBookSkip)

        // Ambient: neither
        let ambient = MediaKind.ambient.behavior
        XCTAssertFalse(ambient.showsScrubbableProgress)
        XCTAssertFalse(ambient.supportsTransportNavigation)
    }

    // MARK: - MediaKind resolution

    func testMusicChannelResolvesToMusicKind() {
        let channel = Channel(
            id: "test", name: "Test", category: "Curated", icon: "music.note",
            contentType: .music, preferredSource: "fma"
        )
        XCTAssertEqual(channel.mediaKind, .music)
    }

    func testAudiobookChannelResolvesToAudiobookKind() {
        let channel = Channel(
            id: "test", name: "Test", category: "Audiobooks", icon: "book.fill",
            contentType: .spokenWord
        )
        XCTAssertEqual(channel.mediaKind, .audiobook)
    }

    func testLectureChannelResolvesToLectureKind() {
        let channel = Channel(
            id: "test", name: "Test", category: "Lectures", icon: "building.columns.fill",
            contentType: .spokenWord, preferredSource: "oxford_lectures"
        )
        XCTAssertEqual(channel.mediaKind, .lecture)
    }

    func testPodcastChannelResolvesToPodcastKind() {
        let channel = Channel(
            id: "test", name: "Test", category: "Podcasts", icon: "newspaper.fill",
            contentType: .spokenWord, feedURL: "https://example.com/feed.xml"
        )
        XCTAssertEqual(channel.mediaKind, .podcast)
    }

    func testAmbientChannelResolvesToAmbientKind() {
        let channel = Channel(
            id: "test", name: "Test", category: "Ambient", icon: "leaf.fill",
            contentType: .ambientLoop
        )
        XCTAssertEqual(channel.mediaKind, .ambient)
    }
}
