import XCTest

final class ChannelBrowseListTests: XCTestCase {

    private func channelBrowseListSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceFile = projectRoot
            .appendingPathComponent("Views")
            .appendingPathComponent("Listen")
            .appendingPathComponent("ChannelBrowseList.swift")
        return try String(contentsOf: sourceFile)
    }

    func testChannelBrowseListUsesPodcastChannelThumbnail() throws {
        let source = try channelBrowseListSource()
        XCTAssertTrue(source.contains("PodcastChannelThumbnail"),
            "ChannelBrowseList must use PodcastChannelThumbnail for podcast artwork thumbnails")
    }

    func testPodcastChannelThumbnailUsesArtworkService() throws {
        let source = try channelBrowseListSource()
        XCTAssertTrue(source.contains("ArtworkService.shared.artwork(fromURLString:"),
            "PodcastChannelThumbnail must use ArtworkService.shared.artwork(fromURLString:) "
            + "for cached local+remote image loading")
    }

    func testPodcastChannelThumbnailUsesChannelImageURL() throws {
        let source = try channelBrowseListSource()
        XCTAssertTrue(source.contains("channel.imageURL"),
            "PodcastChannelThumbnail must reference channel.imageURL to load the thumbnail")
    }
}
