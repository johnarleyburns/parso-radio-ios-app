import XCTest
@testable import ParsoMusic

@MainActor
final class MadeForYouVisibilityTests: XCTestCase {

    private var db: DatabaseService!
    private var tasteStore: TasteProfileStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        tasteStore = TasteProfileStore(db: db)
    }

    override func tearDown() {
        db = nil
        tasteStore = nil
        super.tearDown()
    }

    // MARK: - Scenario 1: Onboarding completed → profile exists → section shows

    func testProfileExistsAfterOnboarding_hasAnyProfileReturnsTrue() async {
        await tasteStore.upsertTerm(bucket: "music", axis: "creator",
                                     term: "bach", increment: 1.0)
        let hasProfile = await tasteStore.hasAnyProfile()
        XCTAssertTrue(hasProfile,
            "hasAnyProfile must return true after onboarding seeds the taste profile")
    }

    func testProfileExistsAfterOnboarding_fetchProfileReturnsNonEmpty() async {
        await tasteStore.upsertTerm(bucket: "music", axis: "creator",
                                     term: "bach", increment: 2.0)
        let profile = await tasteStore.fetchProfile(bucket: "music")
        XCTAssertFalse(profile.isEmpty,
            "Music profile must be non-empty after onboarding")
        XCTAssertTrue(profile.topCreators.contains("bach"),
            "Bach must be in top creators after seeding")
    }

    // MARK: - Scenario 2: Onboarding skipped, no plays → profile empty → cold start

    func testSkipOnboarding_hasAnyProfileReturnsFalse() async {
        let hasProfile = await tasteStore.hasAnyProfile()
        XCTAssertFalse(hasProfile,
            "hasAnyProfile must return false when no taste terms exist (skipped onboarding, no plays)")
    }

    func testSkipOnboarding_fetchProfileReturnsEmpty() async {
        let musicProfile = await tasteStore.fetchProfile(bucket: "music")
        let spokenProfile = await tasteStore.fetchProfile(bucket: "spoken")
        XCTAssertTrue(musicProfile.isEmpty,
            "Music profile must be empty when no taste terms exist")
        XCTAssertTrue(spokenProfile.isEmpty,
            "Spoken profile must be empty when no taste terms exist")
    }

    func testSkipOnboarding_generateQueriesReturnsEmpty() {
        let musicProfile = ProfileBucket(bucket: "music", creatorTerms: [],
                                          subjectTerms: [], composerTerms: [])
        let spokenProfile = ProfileBucket(bucket: "spoken", creatorTerms: [],
                                           subjectTerms: [], composerTerms: [])
        let musicQueries = RecommendationQueryBuilder.generateQueries(
            profile: musicProfile, dateSeed: "2025-06-23",
            allCollectionIDs: ["etree", "musopen"])
        let spokenQueries = RecommendationQueryBuilder.generateQueries(
            profile: spokenProfile, dateSeed: "2025-06-23",
            allCollectionIDs: ["etree", "musopen"])
        XCTAssertTrue(musicQueries.isEmpty,
            "generateQueries must return empty when profile is empty")
        XCTAssertTrue(spokenQueries.isEmpty,
            "generateQueries must return empty when profile is empty")
    }

    // MARK: - Scenario 3: Existing user with play history → profile built from plays

    func testExistingUser_profileBuiltFromPlays() async {
        // Simulate playing a few tracks
        await tasteStore.upsertTerm(bucket: "music", axis: "creator",
                                     term: "chopin", increment: 1.0)
        await tasteStore.upsertTerm(bucket: "music", axis: "creator",
                                     term: "mozart", increment: 1.0)
        await tasteStore.upsertTerm(bucket: "music", axis: "subject",
                                     term: "classical", increment: 1.0)

        let hasProfile = await tasteStore.hasAnyProfile()
        XCTAssertTrue(hasProfile,
            "hasAnyProfile must return true after tracks are played")

        let profile = await tasteStore.fetchProfile(bucket: "music")
        XCTAssertFalse(profile.isEmpty,
            "Profile must be non-empty for existing users with play history")
        XCTAssertTrue(profile.topCreators.contains("chopin")
                        || profile.topCreators.contains("mozart"),
            "Top creators must include played artists")
    }

    func testExistingUser_profileIsolatedByBucket() async {
        await tasteStore.upsertTerm(bucket: "music", axis: "creator",
                                     term: "beethoven", increment: 1.0)
        await tasteStore.upsertTerm(bucket: "spoken", axis: "creator",
                                     term: "mary shelley", increment: 1.0)

        let musicProfile = await tasteStore.fetchProfile(bucket: "music")
        let spokenProfile = await tasteStore.fetchProfile(bucket: "spoken")

        XCTAssertTrue(musicProfile.topCreators.contains("beethoven"),
            "Music profile must contain beethoven")
        XCTAssertFalse(musicProfile.topCreators.contains("mary shelley"),
            "Music profile must not leak spoken creator")
        XCTAssertTrue(spokenProfile.topCreators.contains("mary shelley"),
            "Spoken profile must contain mary shelley")
        XCTAssertFalse(spokenProfile.topCreators.contains("beethoven"),
            "Spoken profile must not leak music creator")
    }

    // MARK: - Transition: profile built after cold start

    func testProfileAppearsAfterFirstPlay_coldStartThenProfile() async {
        // Initially: no profile (cold start state)
        var hasProfile = await tasteStore.hasAnyProfile()
        XCTAssertFalse(hasProfile, "Initially no profile (cold start)")

        // User listens to a track → profile gets seeded
        await tasteStore.upsertTerm(bucket: "music", axis: "creator",
                                     term: "debussy", increment: 1.0)
        hasProfile = await tasteStore.hasAnyProfile()
        XCTAssertTrue(hasProfile,
            "Profile must exist after first track play")

        let profile = await tasteStore.fetchProfile(bucket: "music")
        XCTAssertFalse(profile.isEmpty,
            "Profile must be non-empty after first play")
    }

    // MARK: - Subject stop-list respected

    func testSubjectStopListRespected() async {
        // Seed one stop-listed and one non-stop-listed subject
        await tasteStore.upsertTerm(bucket: "music", axis: "subject",
                                     term: "classical", increment: 5.0)
        await tasteStore.upsertTerm(bucket: "music", axis: "subject",
                                     term: "music", increment: 5.0)
        let profile = await tasteStore.fetchProfile(bucket: "music")

        // Non-stop-listed "classical" must appear above stop-listed "music"
        XCTAssertTrue(profile.topSubjects.contains("classical"),
            "Non-stop-listed subject 'classical' must appear in top subjects")
        // "music" is stop-listed — its weight is near-zero, so it should NOT
        // outrank classical even with the same seed weight
        let classicalIdx = profile.topSubjects.firstIndex(of: "classical") ?? Int.max
        let musicIdx = profile.topSubjects.firstIndex(of: "music") ?? Int.max
        XCTAssertTrue(classicalIdx < musicIdx,
            "Stop-listed 'music' must rank below non-stop-listed 'classical'")
    }
}
