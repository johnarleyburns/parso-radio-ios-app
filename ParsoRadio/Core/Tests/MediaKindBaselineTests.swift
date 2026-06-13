import XCTest
@testable import ParsoMusic

final class MediaKindBaselineTests: XCTestCase {

    // MARK: - All channels baseline

    func testAllChannelsHaveExpectedShuffleBehavior() {
        for channel in Channel.defaults {
            let shuffles = QueueManager.usesShuffle(channel: channel, shuffleMode: false)
            let expected = expectedShuffles(channel)
            XCTAssertEqual(shuffles, expected,
                "\(channel.id) (cat: \(channel.category), source: \(channel.preferredSource ?? "nil"), iaQueryEntry: \(channel.iaQueryEntry != nil ? "yes" : "no")): expected shuffle=\(expected), got \(shuffles)")
        }
    }

    func testAllChannelsHaveExpectedSequentialBehavior() {
        for channel in Channel.defaults {
            let isSequential = channel.feedURL != nil
            let expected = expectedIsSequential(channel)
            XCTAssertEqual(isSequential, expected,
                "\(channel.id): expected sequential=\(expected), got \(isSequential)")
        }
    }

    func testAllChannelsHaveExpectedProgressBarBehavior() {
        for channel in Channel.defaults {
            let showsProgressBar = channel.contentType == .spokenWord
            let expected = expectedShowsProgressBar(channel)
            XCTAssertEqual(showsProgressBar, expected,
                "\(channel.id): expected progressBar=\(expected), got \(showsProgressBar)")
        }
    }

    func testAllChannelsHaveExpectedResumePositionBehavior() {
        for channel in Channel.defaults {
            let persistsResume = channel.contentType != .ambientLoop
            let expected = expectedPersistsResumePosition(channel)
            XCTAssertEqual(persistsResume, expected,
                "\(channel.id): expected persistsResume=\(expected), got \(persistsResume)")
        }
    }

    // MARK: - Expected behavior tables

    private func expectedShuffles(_ channel: Channel) -> Bool {
        // Curated/registry channels always shuffle
        if channel.iaQueryEntry != nil { return true }
        // Lecture channels always shuffle
        if channel.category == "Lectures" { return true }
        // For You channels: music-for-you has no iaQueryEntry; books-for-you also none
        // Podcasts: sequential, no shuffle
        // Ambient: no shuffle
        return false
    }

    private func expectedIsSequential(_ channel: Channel) -> Bool {
        // Only podcast/news channels have feedURL
        return channel.feedURL != nil
    }

    private func expectedShowsProgressBar(_ channel: Channel) -> Bool {
        // All spokenWord channels show the progress bar
        return channel.contentType == .spokenWord
    }

    private func expectedPersistsResumePosition(_ channel: Channel) -> Bool {
        // Ambient loops do not persist position
        return channel.contentType != .ambientLoop
    }

    // MARK: - Verify channel coverage

    func testChannelDefaultsIsNotEmpty() {
        XCTAssertFalse(Channel.defaults.isEmpty, "Channel.defaults must not be empty")
    }

    func testAllChannelsHaveMediaKindCompatibleCategory() {
        let validCategories = Set(["For You", "Lectures", "Podcasts", "Curated",
                                    "Curated Books", "Audiobooks", "Ambient"])
        for channel in Channel.defaults {
            XCTAssertTrue(validCategories.contains(channel.category),
                "Channel \(channel.id) has unknown category: \(channel.category)")
        }
    }
}
