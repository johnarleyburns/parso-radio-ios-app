import XCTest
@testable import ParsoMusic

final class RecommendationQueryBuilderTests: XCTestCase {

    private func track(_ id: String) -> Track {
        Track(
            id: id, source: "internet_archive", title: id, artist: "anon",
            duration: 180, streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil, license: .publicDomain, tags: [],
            qualityScore: 0.8, rawCreator: "anon", composer: nil, instruments: [],
            metadataConfidence: 0.0)
    }

    /// Convenience: build a history list with `(channelId, count)` repetitions.
    /// Tuple shape matches DatabaseService.fetchRecentlyPlayedWithChannel —
    /// `(track, channelId)`. Reordering crashes at runtime, not at compile.
    private func history(_ entries: [(String, Int)]) -> [(track: Track, channelId: String)] {
        var out: [(track: Track, channelId: String)] = []
        var n = 0
        for (cid, count) in entries {
            for _ in 0..<count { out.append((track("t\(n)"), cid)); n += 1 }
        }
        return out
    }

    // MARK: - channelWeights

    func testChannelWeightsHistogramAndProportions() {
        let cat = ["channel-a": "Curated Music", "channel-b": "Curated Music",
                   "channel-c": "Curated Music", "podcast-no-agenda": "Podcasts",
                   "music-for-you": "For You"]
        let h = history([("channel-a", 6), ("channel-b", 3), ("channel-c", 1),
                         ("podcast-no-agenda", 4), ("music-for-you", 2)])
        let ws = RecommendationQueryBuilder.channelWeights(
            fromHistory: h, categoryFilter: ["Curated Music"], categoryById: cat)
        XCTAssertEqual(ws.count, 3, "only Curated Music channels contribute")
        XCTAssertEqual(ws.map(\.channelId), ["channel-a", "channel-b", "channel-c"],
            "sorted by play count desc")
        XCTAssertEqual(ws[0].weight, 0.6, accuracy: 1e-9, "6/10")
        XCTAssertEqual(ws[1].weight, 0.3, accuracy: 1e-9, "3/10")
        XCTAssertEqual(ws[2].weight, 0.1, accuracy: 1e-9, "1/10")
        XCTAssertEqual(ws.reduce(0) { $0 + $1.weight }, 1.0, accuracy: 1e-9, "weights sum to 1")
    }

    func testChannelWeightsEmptyWhenNoRelevantPlays() {
        let cat = ["podcast-no-agenda": "Podcasts"]
        let h = history([("podcast-no-agenda", 5)])
        let ws = RecommendationQueryBuilder.channelWeights(
            fromHistory: h, categoryFilter: ["Curated Music"], categoryById: cat)
        XCTAssertTrue(ws.isEmpty, "no Curated Music plays → empty histogram")
    }

    // MARK: - allocateSamples

    func testAllocationProportionalWithMinFloor() {
        // 60% / 30% / 10% over 100 slots → 60 / 30 / 10. Each ≥ minPerChannel.
        let ws = [
            RecommendationQueryBuilder.ChannelWeight(channelId: "a", plays: 60, weight: 0.6),
            RecommendationQueryBuilder.ChannelWeight(channelId: "b", plays: 30, weight: 0.3),
            RecommendationQueryBuilder.ChannelWeight(channelId: "c", plays: 10, weight: 0.1),
        ]
        let alloc = RecommendationQueryBuilder.allocateSamples(weights: ws, total: 100, minPerChannel: 5)
        XCTAssertEqual(alloc.map(\.count), [60, 30, 10], "proportional with no min collisions")
    }

    func testAllocationMinFloorProtectsLongTail() {
        // 90% / 10% over 100 slots, minPerChannel 15 → second channel bumped to 15.
        let ws = [
            RecommendationQueryBuilder.ChannelWeight(channelId: "big", plays: 90, weight: 0.9),
            RecommendationQueryBuilder.ChannelWeight(channelId: "tiny", plays: 10, weight: 0.1),
        ]
        let alloc = RecommendationQueryBuilder.allocateSamples(weights: ws, total: 100, minPerChannel: 15)
        XCTAssertEqual(alloc.first(where: { $0.channelId == "big" })?.count, 90)
        XCTAssertEqual(alloc.first(where: { $0.channelId == "tiny" })?.count, 15,
            "long-tail channel still gets at least the minimum")
    }
}
