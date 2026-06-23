import XCTest
@testable import ParsoMusic

@MainActor
final class RecommendationQueryBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func makeProfile(bucket: String, creators: [(String, Double)] = [],
                              subjects: [(String, Double)] = [],
                              composers: [(String, Double)] = []) -> ProfileBucket {
        ProfileBucket(
            bucket: bucket,
            creatorTerms: creators.map { TasteTerm(axis: "creator", term: $0.0, weight: $0.1) },
            subjectTerms: subjects.map { TasteTerm(axis: "subject", term: $0.0, weight: $0.1) },
            composerTerms: composers.map { TasteTerm(axis: "composer", term: $0.0, weight: $0.1) }
        )
    }

    private let testCollections = ["tedjonespiano", "sfjazz", "cujazz", "vinyl_bostonpubliclibrary"]

    // MARK: - Generation

    func testExploitQueriesUseTopCreators() {
        let profile = makeProfile(bucket: "music",
                                   creators: [("bach", 10.0), ("mozart", 8.0)],
                                   subjects: [("classical", 5.0)],
                                   composers: [("bach", 10.0)])
        let queries = RecommendationQueryBuilder.generateQueries(
            profile: profile, dateSeed: "2025-01-15", allCollectionIDs: testCollections)

        let exploitQueries = queries.filter { $0.noveltyClass == .exploit }
        XCTAssertFalse(exploitQueries.isEmpty, "should have EXPLOIT queries for top creators")
        for q in exploitQueries {
            XCTAssertTrue(q.iaQuery.contains("creator:"), "EXPLOIT queries should search by creator")
        }
    }

    func testQueryMixHonorsClassRatios() {
        let profile = makeProfile(bucket: "music",
                                   creators: [("bach", 10.0), ("mozart", 8.0), ("chopin", 6.0)],
                                   subjects: [("classical", 10.0), ("piano", 7.0), ("baroque", 5.0), ("romantic", 4.0)],
                                   composers: [("bach", 10.0)])
        let queries = RecommendationQueryBuilder.generateQueries(
            profile: profile, dateSeed: "2025-01-15", allCollectionIDs: testCollections)

        let exploitCount = queries.filter { $0.noveltyClass == .exploit }.map(\.requestedCount).reduce(0, +)
        let exploreCount = queries.filter { $0.noveltyClass == .explore }.map(\.requestedCount).reduce(0, +)
        let serendipityCount = queries.filter { $0.noveltyClass == .serendipity }.map(\.requestedCount).reduce(0, +)
        let total = exploitCount + exploreCount + serendipityCount

        XCTAssertTrue(exploitCount > 0)
        let exploitFraction = Double(exploitCount) / Double(total)
        XCTAssertTrue(exploitFraction >= 0.4 && exploitFraction <= 0.7,
                       "exploit fraction ~0.55, got \(exploitFraction)")
    }

    func testDeterministicUnderFixedDateSeed() {
        let profile = makeProfile(bucket: "music",
                                   creators: [("bach", 10.0)],
                                   subjects: [("classical", 10.0), ("baroque", 5.0)],
                                   composers: [("bach", 8.0)])

        let queries1 = RecommendationQueryBuilder.generateQueries(
            profile: profile, dateSeed: "2025-01-15", allCollectionIDs: testCollections)
        let queries2 = RecommendationQueryBuilder.generateQueries(
            profile: profile, dateSeed: "2025-01-15", allCollectionIDs: testCollections)

        XCTAssertEqual(queries1.count, queries2.count)
        for i in queries1.indices {
            XCTAssertEqual(queries1[i].iaQuery, queries2[i].iaQuery,
                           "same seed must produce identical queries")
        }
    }

    func testDifferentDateSeedProducesDifferentSerendipity() {
        let profile = makeProfile(bucket: "music",
                                   creators: [("bach", 10.0)],
                                   subjects: [("classical", 10.0), ("baroque", 5.0), ("romantic", 4.0), ("opera", 3.0)],
                                   composers: [])

        let queries1 = RecommendationQueryBuilder.generateQueries(
            profile: profile, dateSeed: "2025-01-15", allCollectionIDs: testCollections)
        let queries2 = RecommendationQueryBuilder.generateQueries(
            profile: profile, dateSeed: "2025-01-16", allCollectionIDs: testCollections)

        let exploit1 = queries1.filter { $0.noveltyClass == .exploit }.map(\.iaQuery)
        let exploit2 = queries2.filter { $0.noveltyClass == .exploit }.map(\.iaQuery)
        XCTAssertEqual(exploit1.sorted(), exploit2.sorted(), "EXPLOIT queries stable across days")
    }

    func testEmptyProfileReturnsEmptyQueries() {
        let profile = ProfileBucket(bucket: "music", creatorTerms: [],
                                     subjectTerms: [], composerTerms: [])
        let queries = RecommendationQueryBuilder.generateQueries(
            profile: profile, dateSeed: "2025-01-15", allCollectionIDs: testCollections)
        XCTAssertTrue(queries.isEmpty)
    }

    func testEscapeSolrDoesNotBreakQuery() {
        let profile = makeProfile(bucket: "music",
                                   creators: [("d.j. spooky", 10.0)],
                                   subjects: [("hip-hop", 8.0)])
        let queries = RecommendationQueryBuilder.generateQueries(
            profile: profile, dateSeed: "2025-01-15", allCollectionIDs: testCollections)
        for q in queries {
            XCTAssertFalse(q.iaQuery.contains("&&"), "unescaped && in query")
        }
    }

    func testBuildAdjacentSubjectsExcludesTopPlayed() {
        let profile = makeProfile(bucket: "music",
                                   creators: [],
                                   subjects: [("classical", 10.0), ("piano", 8.0), ("baroque", 6.0),
                                              ("romantic", 4.0), ("chamber", 2.0)])
        let topPlayedSet: Set<String> = ["classical", "piano"]
        let adjacent = RecommendationQueryBuilder.buildAdjacentSubjects(
            from: profile, topPlayedSet: topPlayedSet)

        XCTAssertFalse(adjacent.contains("classical"), "adjacent set must not contain top-played")
        XCTAssertFalse(adjacent.contains("piano"), "adjacent set must not contain top-played")
    }

    func testExtractCollectionsReturnsIDs() {
        let collections: [IACollection] = [
            IACollection(id: "abc", title: "ABC", category: "x", curator: "", icon: ""),
            IACollection(id: "xyz", title: "XYZ", category: "x", curator: "", icon: "")
        ]
        let ids = RecommendationQueryBuilder.extractCollections(from: collections)
        XCTAssertEqual(ids.sorted(), ["abc", "xyz"])
    }
}
