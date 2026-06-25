import XCTest
@testable import ParsoMusic

@MainActor
final class TasteProfileMaintenanceTests: XCTestCase {
    private var db: DatabaseService!
    private var store: TasteProfileStore!

    override func setUp() async throws {
        db = try DatabaseService(path: ":memory:")
        store = TasteProfileStore(db: db)
    }

    private func makeTrack(id: String, title: String, artist: String = "Test Artist",
                            rawCreator: String = "Test Creator",
                            tags: [String] = ["classical", "piano"],
                            composer: String? = "Mozart",
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

    // MARK: - Play recording

    func testPlayRecordsTermsInCorrectBucket() async {
        let track = makeTrack(id: "t1", title: "Classical Piece", rawCreator: "Mozart",
                               tags: ["classical"], composer: "Mozart")
        let channel = Channel(id: "music-ch", name: "Classical", category: "Curated Music",
                               icon: "music.note", tags: ["classical"],
                               preferredSource: "internet_archive")

        await store.seedFromTrack(track, channel: channel)

        let musicProfile = await store.fetchProfile(bucket: "music")
        XCTAssertTrue(musicProfile.creatorTerms.contains { $0.term == "mozart" },
                       "music bucket should contain mozart creator term")
        XCTAssertTrue(musicProfile.composerTerms.contains { $0.term == "mozart" },
                       "music bucket should contain mozart composer term")
        XCTAssertTrue(musicProfile.subjectTerms.contains { $0.term == "classical" },
                       "music bucket should contain classical subject term")
    }

    func testPlayRecordsSeenIdentifier() async {
        let track = makeTrack(id: "t2", title: "Some Track")
        await store.addSeenIdentifiers(from: track, reason: "played")

        let seen = await store.fetchSeenIdentifiers()
        XCTAssertTrue(seen.contains("t2"), "seen set should contain track ID")
    }

    // MARK: - Favorite boost

    func testFavoriteBoostApplied() async {
        let track = makeTrack(id: "t3", title: "Favorite Track", rawCreator: "Chopin",
                               tags: ["piano"], composer: "Chopin")

        // Plain play first
        await store.seedFromTrack(track, channel: nil)
        let afterPlay = await store.fetchProfile(bucket: "music")
        let playWeight = afterPlay.creatorTerms.first { $0.term == "chopin" }?.weight ?? 0

        // Favorite boost
        await store.seedFavoriteBoostFromTrack(track, channel: nil)
        let afterFav = await store.fetchProfile(bucket: "music")
        let favWeight = afterFav.creatorTerms.first { $0.term == "chopin" }?.weight ?? 0

        // Total should be playWeight + 3.0*playWeight-ish (boost multiplier)
        XCTAssertGreaterThan(favWeight, playWeight,
                              "favorite boost should increase weight beyond plain play")
    }

    // MARK: - Cross-context counting (root cause B regression)

    func testPlayFromForYouChannelStillCounts() async {
        let track = makeTrack(id: "t4", title: "From For You", rawCreator: "Bach",
                               tags: ["baroque"])
        let channel = Channel(id: "for-you", name: "For You", category: "For You",
                               icon: "sparkles", tags: ["for-you"],
                               preferredSource: "internet_archive")

        await store.seedFromTrack(track, channel: channel)

        let musicProfile = await store.fetchProfile(bucket: "music")
        let hasBach = musicProfile.creatorTerms.contains { $0.term == "bach" }
        XCTAssertTrue(hasBach, "plays from For You channel must still count (root cause B fix)")
    }

    func testPlayFromSearchStillCounts() async {
        let track = makeTrack(id: "t5", title: "Search Result", rawCreator: "Debussy",
                               tags: ["impressionist"])

        await store.seedFromTrack(track, channel: nil)

        let musicProfile = await store.fetchProfile(bucket: "music")
        let hasDebussy = musicProfile.creatorTerms.contains { $0.term == "debussy" }
        XCTAssertTrue(hasDebussy, "plays from search must count")
    }

    // MARK: - Bucketing without a live channel (root cause: audiobook → music)

    func testNilChannelLibrivoxTrackSeedsSpokenBucket() async {
        let track = makeTrack(id: "lv-t1", title: "Pride and Prejudice",
                               rawCreator: "Jane Austen",
                               tags: [Channel.stampToken("lv-general-fiction")],
                               composer: nil)

        await store.seedFromTrack(track, channel: nil)

        let spoken = await store.fetchProfile(bucket: "spoken")
        XCTAssertTrue(spoken.creatorTerms.contains { $0.term == "jane austen" },
                       "LibriVox-stamped track played without a channel must seed the spoken bucket")

        let music = await store.fetchProfile(bucket: "music")
        XCTAssertFalse(music.creatorTerms.contains { $0.term == "jane austen" },
                        "audiobook author must not pollute the music bucket")
    }

    func testAudiobookChannelSeedsSpokenBucket() async {
        let channel = Channel.defaults.first { $0.category == "Audiobooks" }!
        let track = makeTrack(id: "ab-t1", title: "Moby Dick",
                               rawCreator: "Herman Melville", tags: ["fiction"],
                               composer: nil)

        await store.seedFromTrack(track, channel: channel)

        let spoken = await store.fetchProfile(bucket: "spoken")
        XCTAssertTrue(spoken.creatorTerms.contains { $0.term == "herman melville" },
                       "play from an Audiobooks channel must seed the spoken bucket")
        let music = await store.fetchProfile(bucket: "music")
        XCTAssertFalse(music.creatorTerms.contains { $0.term == "herman melville" })
    }

    // MARK: - Repeated plays

    func testRepeatedPlayDoesNotExplodeWeight() async {
        let track = makeTrack(id: "t6", title: "Repeated", rawCreator: "Artist X",
                               tags: ["genre-x"], composer: nil)

        for _ in 0..<5 {
            await store.seedFromTrack(track, channel: nil)
        }

        let profile = await store.fetchProfile(bucket: "music")
        let weight = profile.creatorTerms.first { $0.term == "artist x" }?.weight ?? 0
        XCTAssertLessThan(weight, 50.0, "repeated plays should not explode weight unboundedly")
    }

    // MARK: - Seen identifiers

    func testFavoriteAddRecordsSeenIdentifier() async {
        let track = makeTrack(id: "t7", title: "Faved Track")
        await store.addSeenIdentifiers(from: track, reason: "favorited")

        let seen = await store.fetchSeenIdentifiers()
        XCTAssertTrue(seen.contains("t7"))
    }

    func testSeenIncludesWorkKey() async {
        let track = makeTrack(id: "t8", title: "Work Track", rawCreator: "Author",
                               parentIdentifier: "some-work")
        await store.addSeenIdentifiers(from: track, reason: "played")

        let seen = await store.fetchSeenIdentifiers()
        XCTAssertTrue(seen.contains("some-work"),
                       "work key (parentIdentifier) should be in seen set")
    }
}
