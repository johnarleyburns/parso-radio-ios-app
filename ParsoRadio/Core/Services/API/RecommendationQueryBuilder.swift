import Foundation

struct CandidateQuery: Equatable {
    let iaQuery: String
    let anchorTerm: String
    let noveltyClass: NoveltyClass
    let requestedCount: Int

    enum NoveltyClass: String, Equatable {
        case exploit
        case explore
        case serendipity
    }
}

/// Where a recommendation shelf draws candidates from, and which content it must
/// exclude. Music scopes to the user's music collections and bars LibriVox /
/// spoken-word; Books targets the LibriVox audiobook collection.
enum RecommendationScope: Equatable {
    case music(collectionIDs: [String])
    case books

    /// A valid trailing Solr clause appended to every generated query. Always
    /// begins with " AND " (or is a bare exclusion when music has no positive
    /// collection scope) so concatenation never produces an empty `()` group.
    var scopeClause: String {
        switch self {
        case .music(let ids):
            let exclusion = " AND NOT collection:librivoxaudio AND NOT subject:\"spoken word\""
            guard !ids.isEmpty else { return exclusion }
            let cols = "(" + ids.map { "collection:\($0)" }.joined(separator: " OR ") + ")"
            return " AND \(cols)\(exclusion)"
        case .books:
            return " AND collection:librivoxaudio"
        }
    }
}

enum RecommendationQueryBuilder {

    /// Backward-compatible overload — treats `allCollectionIDs` as the music scope.
    static func generateQueries(
        profile: ProfileBucket,
        dateSeed: String,
        allCollectionIDs: [String],
        kTarget: Int = RecommendationConstants.kTarget
    ) -> [CandidateQuery] {
        generateQueries(profile: profile, dateSeed: dateSeed,
                        scope: .music(collectionIDs: allCollectionIDs), kTarget: kTarget)
    }

    static func generateQueries(
        profile: ProfileBucket,
        dateSeed: String,
        scope: RecommendationScope,
        kTarget: Int = RecommendationConstants.kTarget
    ) -> [CandidateQuery] {
        guard !profile.isEmpty else { return [] }

        let totalAlloc = kTarget
        let exploitAlloc = Int(Double(totalAlloc) * RecommendationConstants.classMix.exploit)
        let exploreAlloc = Int(Double(totalAlloc) * RecommendationConstants.classMix.explore)
        let serendipityAlloc = totalAlloc - exploitAlloc - exploreAlloc

        var queries: [CandidateQuery] = []

        let scopeClause = scope.scopeClause

        // EXPLOIT: same creator/composer you already love
        let exploitCreators = profile.topCreators + profile.topComposers
        if !exploitCreators.isEmpty, exploitAlloc > 0 {
            let perCreator = max(1, exploitAlloc / exploitCreators.count)
            for creator in exploitCreators {
                let escaped = escapeSolr(creator)
                let query = "(creator:\"\(escaped)\")\(scopeClause)"
                queries.append(CandidateQuery(iaQuery: query, anchorTerm: creator,
                                               noveltyClass: .exploit, requestedCount: perCreator))
            }
        }

        // EXPLORE: subject co-occurrence — pair loved subjects with adjacent
        let exploreSubjects = profile.topSubjects
        if !exploreSubjects.isEmpty, exploreAlloc > 0 {
            let topPlayedSet = Set(profile.topSubjects.map { $0.lowercased() })
            let adjacentCandidates = buildAdjacentSubjects(from: profile, topPlayedSet: topPlayedSet)
            var explorePairs: [(loved: String, adjacent: String)] = []
            for loved in exploreSubjects.prefix(4) {
                if let adj = adjacentCandidates.first(where: { $0 != loved.lowercased() }) {
                    explorePairs.append((loved, adj))
                }
            }
            if explorePairs.isEmpty {
                for loved in exploreSubjects.prefix(2) {
                    let escaped = escapeSolr(loved)
                    let query = "subject:\"\(escaped)\"\(scopeClause)"
                    queries.append(CandidateQuery(iaQuery: query, anchorTerm: loved,
                                                   noveltyClass: .explore, requestedCount: max(1, exploreAlloc / 2)))
                }
            } else {
                let perPair = max(1, exploreAlloc / explorePairs.count)
                for (loved, adjacent) in explorePairs {
                    let escapedLoved = escapeSolr(loved)
                    let escapedAdj = escapeSolr(adjacent)
                    let query = "subject:\"\(escapedLoved)\" AND subject:\"\(escapedAdj)\"\(scopeClause)"
                    queries.append(CandidateQuery(iaQuery: query, anchorTerm: "\(loved)+\(adjacent)",
                                                   noveltyClass: .explore, requestedCount: perPair))
                }
            }
        }

        // SERENDIPITY: top subject crossed with date-seeded sibling subject
        if let topSubject = profile.topSubjects.first, serendipityAlloc > 0 {
            let seed = hashForDate(dateSeed, salt: "serendipity")
            let siblingPool = profile.subjectTerms.dropFirst().map(\.term)
            if !siblingPool.isEmpty {
                let idx = seed % siblingPool.count
                let sibling = siblingPool[idx]
                let escapedTop = escapeSolr(topSubject)
                let escapedSib = escapeSolr(sibling)
                let query = "subject:\"\(escapedTop)\" AND subject:\"\(escapedSib)\" AND mediatype:audio AND downloads:[\(RecommendationConstants.downloadFloor) TO *]\(scopeClause)"
                queries.append(CandidateQuery(iaQuery: query, anchorTerm: "\(topSubject)+\(sibling)",
                                               noveltyClass: .serendipity, requestedCount: serendipityAlloc))
            }
        }

        // If EXPLOIT came up empty, steal from EXPLORE
        if !exploitCreators.isEmpty && queries.filter({ $0.noveltyClass == .exploit }).isEmpty {
            let pc = max(1, exploitAlloc / min(3, exploitCreators.count))
            for creator in exploitCreators.prefix(3) {
                let escaped = escapeSolr(creator)
                let query = "creator:\"\(escaped)\"\(scopeClause)"
                queries.append(CandidateQuery(iaQuery: query, anchorTerm: creator,
                                               noveltyClass: .exploit, requestedCount: pc))
            }
        }

        return queries
    }

    // MARK: - Helpers

    static func buildAdjacentSubjects(from profile: ProfileBucket, topPlayedSet: Set<String>) -> [String] {
        let allTerms = profile.allTerms()
        let topWeighted = Set(profile.topSubjects.map { $0.lowercased() })
        var adjacencyCounts: [String: Int] = [:]
        let subjectSet = Set(profile.subjectTerms.map { $0.term.lowercased() })

        for term in allTerms where subjectSet.contains(term.term) {
            if !topWeighted.contains(term.term) {
                adjacencyCounts[term.term, default: 0] += 1
            }
        }

        return adjacencyCounts
            .filter { !topPlayedSet.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }

    static func extractCollections(from collections: [IACollection]) -> [String] {
        collections.map { $0.id }
    }

    static func hashForDate(_ dateSeed: String, salt: String) -> Int {
        let input = "\(dateSeed):\(salt)"
        return abs(input.hashValue)
    }

    private static func escapeSolr(_ term: String) -> String {
        let specials: Set<Character> = ["+", "-", "!", "(", ")", "{", "}", "[", "]", "^", "\"", "~", "*", "?", ":", "\\", "/"]
        var escaped = ""
        for ch in term {
            if specials.contains(ch) { escaped.append("\\") }
            escaped.append(ch)
        }
        return escaped
    }
}
