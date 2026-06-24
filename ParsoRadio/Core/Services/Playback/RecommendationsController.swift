import Foundation

@MainActor
final class RecommendationsController {
    private let db: DatabaseService
    private let archiveService: InternetArchiveService
    private let tasteStore: TasteProfileStore

    init(db: DatabaseService, archiveService: InternetArchiveService, tasteStore: TasteProfileStore) {
        self.db = db
        self.archiveService = archiveService
        self.tasteStore = tasteStore
    }

    func fetchMixedRecommendations(musicOnly: Bool = false,
                                   booksOnly: Bool = false) async throws -> [Track]? {
        let musicProfile = booksOnly
            ? ProfileBucket(bucket: "music", creatorTerms: [], subjectTerms: [], composerTerms: [])
            : await tasteStore.fetchProfile(bucket: "music")
        let spokenProfile = musicOnly
            ? ProfileBucket(bucket: "spoken", creatorTerms: [], subjectTerms: [], composerTerms: [])
            : await tasteStore.fetchProfile(bucket: "spoken")
        let allCollectionIDs = RecommendationQueryBuilder.extractCollections(
            from: IACollectionStore.shared.collections)

        let dateSeed = dateSeedString()
        let musicQueries = booksOnly ? [] : RecommendationQueryBuilder.generateQueries(
            profile: musicProfile, dateSeed: dateSeed, allCollectionIDs: allCollectionIDs)
        let spokenQueries = musicOnly ? [] : RecommendationQueryBuilder.generateQueries(
            profile: spokenProfile, dateSeed: dateSeed, allCollectionIDs: allCollectionIDs)
        let allQueries = musicQueries + spokenQueries
        guard !allQueries.isEmpty else { return nil }

        let seenIds = await tasteStore.fetchSeenIdentifiers()
        let surfacedIds = await tasteStore.fetchSurfacedIdentifiers()
        let excludeKeys = seenIds.union(surfacedIds)

        let svc = archiveService
        let stampTags = ["for-you"]
        var candidates: [Track] = []

        await withTaskGroup(of: [Track].self) { group in
            for query in allQueries {
                group.addTask {
                    (try? await Self.withTimeout(15) {
                        try await svc.fetchTracks(iaQuery: query.iaQuery, matchTags: stampTags)
                    }) ?? []
                }
            }
            for await tracks in group { candidates.append(contentsOf: tracks) }
        }

        var seen = Set<String>()
        var filtered: [Track] = []
        for c in candidates {
            if excluded(c, excludeKeys: excludeKeys) { continue }
            if seen.insert(c.id).inserted { filtered.append(c) }
        }

        if filtered.count < RecommendationConstants.minShelf {
            let fallbackQueries = buildFallbackQueries(musicProfile: musicProfile,
                                                        spokenProfile: spokenProfile,
                                                        allCollectionIDs: allCollectionIDs)
            var extraCandidates: [Track] = []
            await withTaskGroup(of: [Track].self) { group in
                for query in fallbackQueries {
                    group.addTask {
                        (try? await Self.withTimeout(15) {
                            try await svc.fetchTracks(iaQuery: query, matchTags: stampTags)
                        }) ?? []
                    }
                }
                for await tracks in group { extraCandidates.append(contentsOf: tracks) }
            }
            for c in extraCandidates {
                if excluded(c, excludeKeys: excludeKeys) { continue }
                if seen.insert(c.id).inserted { filtered.append(c) }
            }
        }

        guard !filtered.isEmpty else { return nil }

        let scored = scoreCandidates(filtered, musicProfile: musicProfile, spokenProfile: spokenProfile)
        let topK = greedyMMR(scored, k: RecommendationConstants.kTarget,
                             lambda: RecommendationConstants.lambdaMMR)

        guard topK.count >= RecommendationConstants.minShelf else { return topK.isEmpty ? nil : topK }

        let surfacedKeys = topK.compactMap { t in
            let workKey = tasteStore.workKeyFor(t)
            return workKey != t.id ? [t.id, workKey] : [t.id]
        }.flatMap { $0 }
        await tasteStore.pushSurfaced(surfacedKeys)

        return topK
    }

    // MARK: - Private

    private func dateSeedString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func excluded(_ track: Track, excludeKeys: Set<String>) -> Bool {
        if excludeKeys.contains(track.id) { return true }
        let workKey = tasteStore.workKeyFor(track)
        if workKey != track.id, excludeKeys.contains(workKey) { return true }
        if let parent = track.parentIdentifier, !parent.isEmpty,
           parent != workKey, excludeKeys.contains(parent) { return true }
        return false
    }

    private func scoreCandidates(_ tracks: [Track], musicProfile: ProfileBucket, spokenProfile: ProfileBucket) -> [(track: Track, score: Double)] {
        var allProfileWeights: [String: Double] = [:]
        for t in musicProfile.allTerms() + spokenProfile.allTerms() {
            allProfileWeights[t.term, default: 0] += t.weight
        }
        let profileNorm = allProfileWeights.values.reduce(0) { $0 + $1 * $1 }
        let profileNormSqrt = sqrt(profileNorm)

        var scored: [(track: Track, score: Double)] = []
        for track in tracks {
            let tokens = extractTokens(track)
            var affinity: Double = 0
            for token in tokens {
                affinity += allProfileWeights[token] ?? 0
            }
            let tokenNorm = Double(tokens.count)
            if profileNormSqrt > 0, tokenNorm > 0 {
                affinity = affinity / (profileNormSqrt * sqrt(tokenNorm))
            }
            let popPrior = track.qualityScore > 0
                ? log(1.0 + track.qualityScore) / log(Double(RecommendationConstants.downloadFloor))
                : 0.0
            let pop = min(1.0, popPrior * 0.5)

            let score = RecommendationConstants.wAffinity * affinity
                      + RecommendationConstants.wPop * pop
            scored.append((track, score))
        }
        return scored.sorted { $0.score > $1.score }
    }

    private func extractTokens(_ track: Track) -> [String] {
        var tokens: [String] = []
        let creator = track.rawCreator.lowercased().trimmingCharacters(in: .whitespaces)
        if !creator.isEmpty, creator != "unknown", creator != "various" {
            tokens.append(creator)
        }
        if let composer = track.composer?.lowercased().trimmingCharacters(in: .whitespaces),
           !composer.isEmpty {
            tokens.append(composer)
        }
        for tag in track.tags {
            let t = tag.lowercased().trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !RecommendationConstants.subjectStopList.contains(t) {
                tokens.append(t)
            }
        }
        return Array(Set(tokens))
    }

    private func greedyMMR(_ candidates: [(track: Track, score: Double)],
                           k: Int, lambda: Double) -> [Track] {
        guard !candidates.isEmpty else { return [] }
        var remaining = candidates
        var picked: [Track] = []
        let targetK = min(k, candidates.count)

        while picked.count < targetK, !remaining.isEmpty {
            var bestIdx = 0
            var bestMMR = -Double.infinity
            for i in remaining.indices {
                let s = remaining[i].score
                let maxSim = picked.isEmpty ? 0.0
                    : picked.map { jaccardSimilarity(remaining[i].track, $0) }.max() ?? 0.0
                let mmr = s - lambda * maxSim
                if mmr > bestMMR { bestMMR = mmr; bestIdx = i }
            }
            picked.append(remaining[bestIdx].track)
            remaining.remove(at: bestIdx)
        }
        return picked
    }

    private func jaccardSimilarity(_ a: Track, _ b: Track) -> Double {
        let tokensA = Set(extractTokens(a))
        let tokensB = Set(extractTokens(b))
        let intersection = tokensA.intersection(tokensB).count
        let union = tokensA.union(tokensB).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func buildFallbackQueries(musicProfile: ProfileBucket,
                                       spokenProfile: ProfileBucket,
                                       allCollectionIDs: [String]) -> [String] {
        var queries: [String] = []
        let musicCollections = allCollectionIDs.map { "collection:\($0)" }.joined(separator: " OR ")

        for creator in (musicProfile.topCreators + spokenProfile.topCreators).prefix(5) {
            let query = "creator:\"\(creator.replacingOccurrences(of: "\"", with: ""))\" AND (\(musicCollections))"
            queries.append(query)
        }
        for subject in (musicProfile.topSubjects + spokenProfile.topSubjects).prefix(5) {
            let query = "subject:\"\(subject.replacingOccurrences(of: "\"", with: ""))\" AND (\(musicCollections))"
            queries.append(query)
        }
        return Array(Set(queries)).shuffled()
    }

    private static func withTimeout<T>(_ seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
