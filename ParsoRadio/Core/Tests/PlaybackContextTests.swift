import XCTest
@testable import ParsoMusic

final class PlaybackContextTests: XCTestCase {

    func testBookForYouContextSetsAudiobookMediaKind() {
        let context = PlaybackContext(
            origin: .bookForYou,
            mediaKind: .audiobook,
            title: "Pride and Prejudice"
        )
        XCTAssertEqual(context.mediaKind, .audiobook)
        XCTAssertEqual(context.origin, .bookForYou)
        XCTAssertTrue(context.persistsResumePosition)
        XCTAssertEqual(context.contentMode, .spokenWord)
    }

    func testLiveMusicContextSetsMusicMediaKind() {
        let context = PlaybackContext(
            origin: .liveMusic,
            mediaKind: .music,
            title: "Grateful Dead Live"
        )
        XCTAssertEqual(context.mediaKind, .music)
        XCTAssertEqual(context.origin, .liveMusic)
        XCTAssertFalse(context.persistsResumePosition)
        XCTAssertEqual(context.contentMode, .music)
    }

    func testChannelContextSetsChannelMediaKind() {
        let context = PlaybackContext(
            origin: .channel,
            mediaKind: .podcast,
            title: "My Podcast",
            channelId: "ch1"
        )
        XCTAssertEqual(context.mediaKind, .podcast)
        XCTAssertEqual(context.contentMode, .spokenWord)
    }

    func testMadeForYouContextSetsExplicitMediaKind() {
        let context = PlaybackContext(
            origin: .madeForYou,
            mediaKind: .music,
            title: "Fresh Picks"
        )
        XCTAssertEqual(context.mediaKind, .music)
        XCTAssertEqual(context.contentMode, .music)
    }

    func testSearchContextUsesSearchScope() {
        let musicSearch = PlaybackContext(
            origin: .search,
            mediaKind: .music,
            title: "Search Results"
        )
        XCTAssertEqual(musicSearch.mediaKind, .music)

        let audiobookSearch = PlaybackContext(
            origin: .search,
            mediaKind: .audiobook,
            title: "Search Results"
        )
        XCTAssertEqual(audiobookSearch.mediaKind, .audiobook)
    }

    func testAudiobookLecturePodcastUseSpokenWordContentMode() {
        for kind: MediaKind in [.audiobook, .lecture, .podcast] {
            let context = PlaybackContext(origin: .channel, mediaKind: kind, title: "Test")
            XCTAssertEqual(context.contentMode, .spokenWord, "\(kind) should use spokenWord content mode")
        }
    }

    func testMusicAndAmbientUseMusicContentMode() {
        for kind: MediaKind in [.music, .ambient] {
            let context = PlaybackContext(origin: .channel, mediaKind: kind, title: "Test")
            XCTAssertEqual(context.contentMode, .music, "\(kind) should use music content mode")
        }
    }
}
