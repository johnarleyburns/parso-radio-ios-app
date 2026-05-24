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

    // Below the minimum history → nil (caller shows the "listen to N tracks" prompt).
    func testReturnsNilBelowMinimumHistory() {
        let few = (0..<(RecommendationQueryBuilder.minPlays - 1)).map {
            track("t\($0)", artist: "Segovia")
        }
        XCTAssertNil(RecommendationQueryBuilder.musicQuery(fromHistory: few))
        XCTAssertNil(RecommendationQueryBuilder.booksQuery(fromHistory: few))
    }

    // Enough history → a query that boosts the most-played creators and excludes
    // the other medium (spoken word / audiobook collections for Music).
    func testMusicQueryFavorsTopCreatorsAndExcludesSpokenWord() {
        var hist = [Track]()
        for _ in 0..<4 { hist.append(track(UUID().uuidString, artist: "Andrés Segovia")) }
        for _ in 0..<2 { hist.append(track(UUID().uuidString, artist: "Julian Bream")) }
        let q = RecommendationQueryBuilder.musicQuery(fromHistory: hist)
        XCTAssertNotNil(q)
        XCTAssertTrue(q!.contains("creator:\"Andrés Segovia\"^3"))
        XCTAssertTrue(q!.contains("creator:\"Julian Bream\"^3"))
        XCTAssertTrue(q!.contains("collection:librivoxaudio"),
            "Music must EXCLUDE the audiobook collection")
        XCTAssertTrue(q!.contains("NOT ("), "Music must have an exclusion clause")
    }

    // Books query is scoped to the audiobook collections.
    func testBooksQueryScopedToAudiobookCollections() {
        let hist = (0..<6).map { track("b\($0)", artist: "Mark Twain", tags: ["fiction"]) }
        let q = RecommendationQueryBuilder.booksQuery(fromHistory: hist)
        XCTAssertNotNil(q)
        XCTAssertTrue(q!.contains("collection:librivoxaudio")
            && q!.contains("collection:audio_bookspoetry"),
            "Books must be limited to the audiobook collections")
        XCTAssertTrue(q!.contains("creator:\"Mark Twain\"^3"))
    }

    // The "Unknown" placeholder artist must never anchor a query.
    func testIgnoresUnknownArtist() {
        let hist = (0..<6).map { track("u\($0)", artist: "Unknown") }
        // No real creators → nil (nothing to recommend from).
        XCTAssertNil(RecommendationQueryBuilder.musicQuery(fromHistory: hist))
    }

    // topValues ranks by frequency, most-played first.
    func testTopValuesByFrequency() {
        let v = ["a", "b", "a", "c", "a", "b"]
        XCTAssertEqual(RecommendationQueryBuilder.topValues(v, limit: 2), ["a", "b"])
    }
}
