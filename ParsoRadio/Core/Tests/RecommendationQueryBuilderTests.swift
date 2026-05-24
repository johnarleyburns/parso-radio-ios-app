import XCTest
@testable import ParsoMusic

final class RecommendationQueryBuilderTests: XCTestCase {

    private func track(_ id: String, artist: String, tags: [String] = []) -> Track {
        Track(
            id: id, source: "internet_archive", title: id, artist: artist,
            duration: 180, streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil, license: .publicDomain, tags: tags,
            qualityScore: 0.8, rawCreator: artist, composer: nil, instruments: [],
            metadataConfidence: 0.0)
    }

    // Below the minimum history → both arms nil (caller shows the prompt).
    func testReturnsNilBelowMinimumHistory() {
        let few = (0..<(RecommendationQueryBuilder.minPlays - 1)).map {
            track("t\($0)", artist: "Segovia", tags: ["classical"])
        }
        XCTAssertNil(RecommendationQueryBuilder.musicCreatorQuery(fromHistory: few))
        XCTAssertNil(RecommendationQueryBuilder.musicSubjectQuery(fromHistory: few))
        XCTAssertNil(RecommendationQueryBuilder.booksCreatorQuery(fromHistory: few))
        XCTAssertNil(RecommendationQueryBuilder.booksSubjectQuery(fromHistory: few))
    }

    // Music creator arm: only the played creators, the download floor, the
    // exclusion clause — and NO subject arm (that's the discovery query's job).
    func testMusicCreatorArmIsCreatorsOnly() {
        var hist = [Track]()
        for _ in 0..<4 { hist.append(track(UUID().uuidString, artist: "Andrés Segovia", tags: ["guitar"])) }
        for _ in 0..<2 { hist.append(track(UUID().uuidString, artist: "Julian Bream", tags: ["guitar"])) }
        let q = RecommendationQueryBuilder.musicCreatorQuery(fromHistory: hist)
        XCTAssertNotNil(q)
        XCTAssertTrue(q!.contains("creator:\"Andrés Segovia\""))
        XCTAssertTrue(q!.contains("creator:\"Julian Bream\""))
        XCTAssertFalse(q!.contains("subject:\"guitar\""), "creator arm must not carry a subject arm")
        XCTAssertFalse(q!.contains("^3"), "boosts are inert under sort=random and must be dropped")
        XCTAssertTrue(q!.contains("downloads:[\(RecommendationQueryBuilder.downloadsFloor) TO *]"),
            "music arms must apply the download floor")
        XCTAssertTrue(q!.contains("collection:librivoxaudio"), "music must EXCLUDE the audiobook collection")
        XCTAssertTrue(q!.contains("NOT ("), "music must have an exclusion clause")
    }

    // Music subject arm: only the played subjects + floor + exclusions, no creators.
    func testMusicSubjectArmIsSubjectsOnly() {
        let hist = (0..<6).map { track("m\($0)", artist: "Various", tags: ["Classical"]) }
        let q = RecommendationQueryBuilder.musicSubjectQuery(fromHistory: hist)
        XCTAssertNotNil(q)
        XCTAssertTrue(q!.contains("subject:\"Classical\""))
        XCTAssertFalse(q!.contains("creator:"), "subject arm must not carry a creator arm")
        XCTAssertTrue(q!.contains("downloads:[\(RecommendationQueryBuilder.downloadsFloor) TO *]"))
    }

    // Books arms are scoped to the audiobook collections and carry no music floor.
    func testBooksArmsScopedToAudiobookCollections() {
        let hist = (0..<6).map { track("b\($0)", artist: "Mark Twain", tags: ["fiction"]) }
        let qc = RecommendationQueryBuilder.booksCreatorQuery(fromHistory: hist)
        let qs = RecommendationQueryBuilder.booksSubjectQuery(fromHistory: hist)
        XCTAssertNotNil(qc); XCTAssertNotNil(qs)
        for q in [qc!, qs!] {
            XCTAssertTrue(q.contains("collection:librivoxaudio") && q.contains("collection:audio_bookspoetry"),
                "books must be limited to the audiobook collections")
            XCTAssertFalse(q.contains("downloads:["), "books arms use no download floor")
        }
        XCTAssertTrue(qc!.contains("creator:\"Mark Twain\""))
        XCTAssertTrue(qs!.contains("subject:\"fiction\""))
    }

    // The "Unknown" placeholder artist must never anchor the creator arm; with no
    // subjects either, both arms are nil (nothing to recommend from).
    func testIgnoresUnknownArtist() {
        let hist = (0..<6).map { track("u\($0)", artist: "Unknown") }
        XCTAssertNil(RecommendationQueryBuilder.musicCreatorQuery(fromHistory: hist))
        XCTAssertNil(RecommendationQueryBuilder.musicSubjectQuery(fromHistory: hist))
    }

    // topValues ranks by frequency, most-played first.
    func testTopValuesByFrequency() {
        let v = ["a", "b", "a", "c", "a", "b"]
        XCTAssertEqual(RecommendationQueryBuilder.topValues(v, limit: 2), ["a", "b"])
    }

    // mixPool biases the pool to the creator (signal) arm at the configured share,
    // fills the remainder from the subject arm, caps at `total`, and dedupes.
    func testMixPoolBiasesToCreatorsAndCaps() {
        let creators = (0..<100).map { track("c\($0)", artist: "A") }
        let subjects = (0..<100).map { track("s\($0)", artist: "B") }
        let pool = RecommendationQueryBuilder.mixPool(
            creatorTracks: creators, subjectTracks: subjects, total: 120, creatorShare: 0.7)
        XCTAssertEqual(pool.count, 120, "pool is capped at total")
        let fromCreators = pool.filter { $0.id.hasPrefix("c") }.count
        XCTAssertEqual(fromCreators, 84, "70% of 120 comes from the creator arm")
        XCTAssertEqual(Set(pool.map(\.id)).count, pool.count, "pool is deduped")
    }

    // A thin subject arm must NOT shrink the pool — it tops up from creators.
    func testMixPoolThinSubjectTopsUpFromCreators() {
        let creators = (0..<100).map { track("c\($0)", artist: "A") }
        let subjects = (0..<5).map { track("s\($0)", artist: "B") }
        let pool = RecommendationQueryBuilder.mixPool(
            creatorTracks: creators, subjectTracks: subjects, total: 120, creatorShare: 0.7)
        XCTAssertEqual(pool.count, 105, "100 creator + 5 subject when the subject arm is thin")
        XCTAssertEqual(pool.filter { $0.id.hasPrefix("c") }.count, 100)
    }

    // Overlapping ids across arms appear once.
    func testMixPoolDedupesAcrossArms() {
        let creators = [track("dup", artist: "A"), track("c1", artist: "A")]
        let subjects = [track("dup", artist: "B"), track("s1", artist: "B")]
        let pool = RecommendationQueryBuilder.mixPool(
            creatorTracks: creators, subjectTracks: subjects, total: 120, creatorShare: 0.7)
        XCTAssertEqual(pool.filter { $0.id == "dup" }.count, 1, "a shared id appears once")
    }
}
