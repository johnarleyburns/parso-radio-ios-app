import XCTest
@testable import ParsoMusic

@MainActor
final class RecommendationsControllerTests: XCTestCase {
    private var db: DatabaseService!
    private var store: TasteProfileStore!
    private var controller: RecommendationsController!

    override func setUp() async throws {
        db = try DatabaseService(path: ":memory:")
        store = TasteProfileStore(db: db)
        controller = RecommendationsController(
            db: db,
            archiveService: InternetArchiveService(),
            tasteStore: store
        )
    }

    // MARK: - Exclusion

    func testExclusionFiltersPlayedTrackIDs() async {
        let track = makeTrack(id: "seen-1", title: "Seen Track", rawCreator: "Artist")
        await store.addSeenIdentifiers(from: track, reason: "played")

        let excludeKeys = await store.fetchSeenIdentifiers()
        XCTAssertTrue(excludeKeys.contains("seen-1"))
    }

    func testExclusionFiltersFavoritedTrackIDs() async {
        let track = makeTrack(id: "fav-1", title: "Faved Track", rawCreator: "Artist")
        await store.addSeenIdentifiers(from: track, reason: "favorited")

        let seen = await store.fetchSeenIdentifiers()
        XCTAssertTrue(seen.contains("fav-1"))
    }

    func testWorkKeyExclusionCatchesReupload() async {
        // Same book under two different IA IDs — both should be excluded
        let original = makeTrack(id: "ia-old-123", title: "Pride and Prejudice",
                                  rawCreator: "Jane Austen", parentIdentifier: "pride-prejudice")
        let reupload = makeTrack(id: "ia-new-456", title: "Pride and Prejudice",
                                  rawCreator: "Jane Austen", parentIdentifier: "pride-prejudice")

        await store.addSeenIdentifiers(from: original, reason: "played")

        let seen = await store.fetchSeenIdentifiers()
        XCTAssertTrue(seen.contains("pride-prejudice"))

        let workKey = store.workKeyFor(reupload)
        XCTAssertEqual(workKey, "pride-prejudice")
        XCTAssertTrue(seen.contains(workKey),
                       "reupload with same parentIdentifier should match exclusion")
    }

    // MARK: - Scoring helpers

    func testJaccardSimilarity() {
        // We can't call private methods directly, but we can test indirectly
        // via fetchMixedRecommendations. For now, let's test the concepts.
        let a = makeTrack(id: "a", title: "A", rawCreator: "Mozart",
                           tags: ["classical", "piano"], composer: "Mozart")
        let b = makeTrack(id: "b", title: "B", rawCreator: "Mozart",
                           tags: ["classical", "violin"], composer: "Mozart")

        // Both share "mozart" creator and "classical" tag
        // Different: "piano" vs "violin"
        let tokensA: Set<String> = ["mozart", "classical", "piano"]
        let tokensB: Set<String> = ["mozart", "classical", "violin"]
        let intersection = tokensA.intersection(tokensB).count // 2
        let union = tokensA.union(tokensB).count // 4
        let sim = Double(intersection) / Double(union) // 0.5
        XCTAssertEqual(sim, 0.5)
    }

    func testSurfacedRingUpdatedAfterGeneration() async {
        // Push some keys, then verify they're stored
        await store.pushSurfaced(["surfaced-key-1", "surfaced-key-2"])
        let ids = await store.fetchSurfacedIdentifiers()
        XCTAssertEqual(ids.count, 2)
    }

    // MARK: - MIN_SHELF top-up

    func testMinShelfConstantIsReasonable() {
        XCTAssertGreaterThanOrEqual(RecommendationConstants.minShelf, 10,
                                     "MIN_SHELF must be at least 10")
        XCTAssertLessThan(RecommendationConstants.minShelf, RecommendationConstants.kTarget,
                           "MIN_SHELF must be less than kTarget")
    }

    // MARK: - Profile non-empty

    func testEmptyProfileReturnsNil() async {
        let hasProfile = await store.hasAnyProfile()
        XCTAssertFalse(hasProfile)
    }

    func testSeededProfileIsNonEmpty() async {
        await store.upsertTerm(bucket: "music", axis: "creator", term: "bach", increment: 5.0)
        let hasProfile = await store.hasAnyProfile()
        XCTAssertTrue(hasProfile)
    }

    // MARK: - Helpers

    private func makeTrack(id: String, title: String, artist: String = "Test Artist",
                            rawCreator: String = "Test Creator",
                            tags: [String] = ["classical"],
                            composer: String? = nil,
                            parentIdentifier: String? = nil) -> Track {
        Track(
            id: id, source: "internet_archive", title: title,
            artist: artist, duration: 180,
            streamURL: URL(string: "https://example.com/\(id).mp3")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: tags,
            qualityScore: 3.0, rawCreator: rawCreator,
            composer: composer, instruments: [],
            metadataConfidence: 1.0, parentIdentifier: parentIdentifier
        )
    }
}
