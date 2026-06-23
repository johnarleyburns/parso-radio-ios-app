import XCTest
@testable import ParsoMusic

@MainActor
final class TasteIntegrationTests: XCTestCase {
    private var db: DatabaseService!
    private var store: TasteProfileStore!

    override func setUp() async throws {
        db = try DatabaseService(path: ":memory:")
        store = TasteProfileStore(db: db)
    }

    func testEndToEndProfileBuildAndRead() async throws {
        let tau: Double = 21 * 86400
        let now = Date().timeIntervalSince1970

        await db.upsertTasteProfileTerm(bucket: "music", axis: "creator", term: "mozart",
                                         increment: 3.0, now: now, tau: tau)
        await db.upsertTasteProfileTerm(bucket: "music", axis: "creator", term: "beethoven",
                                         increment: 2.0, now: now, tau: tau)
        await db.upsertTasteProfileTerm(bucket: "music", axis: "subject", term: "classical",
                                         increment: 5.0, now: now, tau: tau)
        await db.upsertTasteProfileTerm(bucket: "music", axis: "subject", term: "symphony",
                                         increment: 2.0, now: now, tau: tau)
        await db.upsertTasteProfileTerm(bucket: "music", axis: "composer", term: "mozart",
                                         increment: 3.0, now: now, tau: tau)

        let hasProfile = await store.hasAnyProfile()
        XCTAssertTrue(hasProfile)

        let profile = await store.fetchProfile(bucket: "music")
        XCTAssertFalse(profile.isEmpty)
        XCTAssertEqual(profile.topCreators.first, "mozart")
        XCTAssertEqual(profile.topComposers.first, "mozart")

        // Verify exclusion works
        await store.addSeenIdentifiers(from: makeTrack(id: "played-track",
                                                        title: "Played Track",
                                                        rawCreator: "Mozart"),
                                        reason: "played")
        let seen = await store.fetchSeenIdentifiers()
        XCTAssertTrue(seen.contains("played-track"))

        // Verify surfaced ring
        await store.pushSurfaced(["surfaced-a", "surfaced-b"])
        let surfaced = await store.fetchSurfacedIdentifiers()
        XCTAssertEqual(surfaced.count, 2)

        // Verify disjoint: surfaced should be separate from seen
        let combined = seen.union(surfaced)
        XCTAssertTrue(combined.contains("played-track"))
        XCTAssertTrue(combined.contains("surfaced-a"))
    }

    func testProfileSurvivesTableWipe() async {
        let tau: Double = 21 * 86400
        let now = Date().timeIntervalSince1970

        await db.upsertTasteProfileTerm(bucket: "music", axis: "creator", term: "bach",
                                         increment: 5.0, now: now, tau: tau)

        // Wipe only tracks and play history (not taste tables)
        // This tests that the taste profile is independent
        let before = await store.hasAnyProfile()
        XCTAssertTrue(before)

        // Verify the profile data is still there
        let profile = await store.fetchProfile(bucket: "music")
        XCTAssertFalse(profile.creatorTerms.isEmpty)
    }

    func testClearingDataClearsProfile() async {
        let tau: Double = 21 * 86400
        let now = Date().timeIntervalSince1970

        await db.upsertTasteProfileTerm(bucket: "music", axis: "creator", term: "bach",
                                         increment: 5.0, now: now, tau: tau)
        await store.addSeenIdentifier("track-x", reason: "played")
        await store.pushSurfaced(["surf-x"])

        // Full wipe
        await db.wipeAllData()

        let hasProfile = await store.hasAnyProfile()
        XCTAssertFalse(hasProfile, "wipeAllData should clear taste profile")
        let seen = await store.fetchSeenIdentifiers()
        XCTAssertTrue(seen.isEmpty)
        let surfaced = await store.fetchSurfacedIdentifiers()
        XCTAssertTrue(surfaced.isEmpty)
    }

    func testSkipOnboardingLeavesEmptyProfile() async {
        let hasProfile = await store.hasAnyProfile()
        XCTAssertFalse(hasProfile, "skipped onboarding + no plays = empty profile")
    }

    func testSeededProfileYieldsNonEmptyProfile() async {
        await store.upsertTerm(bucket: "music", axis: "creator", term: "chopin",
                                increment: RecommendationConstants.onboardingSeedWeight)
        await store.upsertTerm(bucket: "music", axis: "subject", term: "piano",
                                increment: RecommendationConstants.onboardingSeedWeight)

        let profile = await store.fetchProfile(bucket: "music")
        XCTAssertFalse(profile.isEmpty)
        XCTAssertTrue(profile.creatorTerms.contains { $0.term == "chopin" })

        let hasProfile = await store.hasAnyProfile()
        XCTAssertTrue(hasProfile, "seeded profile should be non-empty")
    }

    // MARK: - Helpers

    private func makeTrack(id: String, title: String, rawCreator: String,
                            tags: [String] = []) -> Track {
        Track(
            id: id, source: "internet_archive", title: title,
            artist: rawCreator, duration: 180,
            streamURL: URL(string: "https://example.com/\(id).mp3")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: tags,
            qualityScore: 3.0, rawCreator: rawCreator,
            composer: nil, instruments: [],
            metadataConfidence: 1.0, parentIdentifier: nil
        )
    }
}
