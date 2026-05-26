import Foundation

/// "For You" recommendation policy. Pure & deterministic (given the same history
/// → same output) so it's fully unit-testable. See RECOMMENDATIONS-DESIGN.md.
///
/// PHILOSOPHY (this round): "Curated for you", not "more like the metadata of
/// what you played." Earlier two-arm (creator OR subject across all of IA) let
/// 78rpm / amateur / mis-tagged items leak in — the actual played CHANNELS
/// already encode a quality decision the user trusts. So instead: count plays
/// per channel, weight the recommendation pool by that proportion, and draw
/// tracks from each channel's OWN native registry query. Music for You ends up
/// being a mix of the curated channels you actually use, weighted by how much
/// you use them. Books for You is the same idea over the LibriVox genres.
enum RecommendationQueryBuilder {
    /// Minimum total qualifying plays before a recommendation channel turns on.
    static let minPlays = 5
    /// Target size of the recommendation pool the caller fetches.
    static let poolSize = 120
    /// Minimum slots per contributing channel, so a long-tail channel still gets
    /// represented and a single dominant channel can't crowd everything out.
    static let minPerChannel = 5

    /// One channel's share of the pool.
    struct ChannelWeight: Equatable {
        let channelId: String
        let plays: Int
        let weight: Double         // proportion of relevant plays (Σ = 1.0)
    }

    /// Histogram of plays per channel, filtered to the relevant categories
    /// (Curated for Music, Audiobooks for Books), normalised so weights sum to
    /// 1.0. Sorted by plays desc, with channelId as a deterministic tie-break.
    static func channelWeights(
        fromHistory history: [(channelId: String, track: Track)],
        categoryFilter: Set<String>,
        categoryById: [String: String]
    ) -> [ChannelWeight] {
        var counts: [String: Int] = [:]
        for pair in history where categoryFilter.contains(categoryById[pair.channelId] ?? "") {
            counts[pair.channelId, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return counts
            .map { ChannelWeight(channelId: $0.key, plays: $0.value,
                                 weight: Double($0.value) / Double(total)) }
            .sorted { lhs, rhs in
                if lhs.plays != rhs.plays { return lhs.plays > rhs.plays }
                return lhs.channelId < rhs.channelId
            }
    }

    /// Allocate `total` slots across weighted channels. Each channel gets at
    /// least `minPerChannel` so the long tail isn't starved. Slight overshoot of
    /// the target is OK — the caller treats `total` as a target, not a cap.
    static func allocateSamples(
        weights: [ChannelWeight],
        total: Int = poolSize,
        minPerChannel: Int = minPerChannel
    ) -> [(channelId: String, count: Int)] {
        weights.map { w in
            let raw = Int((Double(total) * w.weight).rounded())
            return (w.channelId, max(minPerChannel, raw))
        }
    }
}
