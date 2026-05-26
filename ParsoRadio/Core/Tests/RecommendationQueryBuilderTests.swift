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
    private func history(_ entries: [(String, Int)]) -> [(channelId: String, track: Track)] {
        var out: [(channelId: String, track: Track)] = []
        var n = 0
        for (cid, count) in entries {
            for _ in 0..<count { out.append((cid, track("t\(n)"))); n += 1 }
        }
        return out
    }

    // MARK: - channelWeights

    func testChannelWeightsHistogramAndProportions() {
        let cat = ["chamber-music": "Curated", "guitar-classical": "Curated",
                   "piano-hour": "Curated", "news-pbs-newshour": "News",
                   "music-for-you": "For You"]
        // 6 chamber, 3 guitar, 1 piano, plus excluded plays (news, for-you).
        let h = history([("chamber-music", 6), ("guitar-classical", 3), ("piano-hour", 1),
                         ("news-pbs-newshour", 4), ("music-for-you", 2)])
        let ws = RecommendationQueryBuilder.channelWeights(
            fromHistory: h, categoryFilter: ["Curated"], categoryById: cat)
        XCTAssertEqual(ws.count, 3, "only Curated channels contribute")
        XCTAssertEqual(ws.map(\.channelId), ["chamber-music", "guitar-classical", "piano-hour"],
            "sorted by play count desc")
        XCTAssertEqual(ws[0].weight, 0.6, accuracy: 1e-9, "6/10")
        XCTAssertEqual(ws[1].weight, 0.3, accuracy: 1e-9, "3/10")
        XCTAssertEqual(ws[2].weight, 0.1, accuracy: 1e-9, "1/10")
        XCTAssertEqual(ws.reduce(0) { $0 + $1.weight }, 1.0, accuracy: 1e-9, "weights sum to 1")
    }

    func testChannelWeightsEmptyWhenNoRelevantPlays() {
        let cat = ["news-pbs-newshour": "News"]
        let h = history([("news-pbs-newshour", 5)])
        let ws = RecommendationQueryBuilder.channelWeights(
            fromHistory: h, categoryFilter: ["Curated"], categoryById: cat)
        XCTAssertTrue(ws.isEmpty, "no Curated plays → empty histogram")
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
