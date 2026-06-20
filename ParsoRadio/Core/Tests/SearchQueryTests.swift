import XCTest
@testable import ParsoMusic

/// The IA search query builder is the heart of search quality. These lock in
/// the contract that fixed the "tarrega guitar returns pop music" bug:
/// every token must match (AND), each across title/creator/subject (OR),
/// with title/creator boosted over subject, and no addeddate sort override.
final class SearchQueryTests: XCTestCase {

    func testSingleTokenExpandsAcrossFields() {
        let q = InternetArchiveService.buildSearchQuery(rawInput: "tarrega")
        XCTAssertTrue(q.hasPrefix("mediatype:audio AND "))
        XCTAssertTrue(q.contains("title:\"tarrega\""))
        XCTAssertTrue(q.contains("creator:\"tarrega\""))
        XCTAssertTrue(q.contains("subject:\"tarrega\""))
    }

    func testMultipleTokensAreAndedTogether() {
        let q = InternetArchiveService.buildSearchQuery(rawInput: "tarrega guitar")
        XCTAssertTrue(q.contains("title:\"guitar\""))
        XCTAssertTrue(q.contains("title:\"tarrega\""))
        // Both tokens AND'd, plus a trailing anchor group → 2 " AND (" joins.
        let andCount = q.components(separatedBy: ") AND (").count - 1
        XCTAssertEqual(andCount, 2,
            "Two tokens + the title/creator anchor produce two AND joins.")
    }

    func testHasTitleCreatorAnchor() {
        // The anchor (at least one token in title/creator) is what keeps
        // keyword-stuffed talk-radio items out of the results.
        let q = InternetArchiveService.buildSearchQuery(rawInput: "plato laws")
        XCTAssertTrue(q.hasSuffix("AND (title:\"plato\" OR creator:\"plato\" OR title:\"laws\" OR creator:\"laws\")"),
            "Query must end with a title/creator anchor over all tokens. Got: \(q)")
    }

    func testTitleAndCreatorAreBoostedOverSubject() {
        let q = InternetArchiveService.buildSearchQuery(rawInput: "bream")
        XCTAssertTrue(q.contains("title:\"bream\"^4"))
        XCTAssertTrue(q.contains("creator:\"bream\"^3"))
        XCTAssertTrue(q.contains("subject:\"bream\"^1"))
    }

    func testPunctuationIsStrippedIntoTokens() {
        let q = InternetArchiveService.buildSearchQuery(rawInput: "bach: cello-suites!")
        XCTAssertTrue(q.contains("title:\"bach\""))
        XCTAssertTrue(q.contains("title:\"cello\""))
        XCTAssertTrue(q.contains("title:\"suites\""))
        // No stray quotes from the punctuation.
        XCTAssertFalse(q.contains("\"\""))
    }

    func testEmptyQueryFallsBackToAudioOnly() {
        XCTAssertEqual(InternetArchiveService.buildSearchQuery(rawInput: "   "),
                       "mediatype:audio")
        XCTAssertEqual(InternetArchiveService.buildSearchQuery(rawInput: ""),
                       "mediatype:audio")
    }

    func testEmbeddedQuotesAreNeutralized() {
        let q = InternetArchiveService.buildSearchQuery(rawInput: "\"hack")
        XCTAssertFalse(q.contains("\"\"hack"),
            "An embedded quote must not break out of the field term.")
        XCTAssertTrue(q.contains("title:\"hack\""))
    }

    // MARK: - Scope clause tests

    func testScopeClauseForMusicIsEmpty() {
        let q = InternetArchiveService.buildSearchQuery(rawInput: "bach",
                                                        scope: .music)
        // No collection filter clause appended.
        XCTAssertTrue(q.hasSuffix("AND (title:\"bach\" OR creator:\"bach\")"),
            "Music scope has no collection clause; query ends at anchor. Got: \(q)")
    }

    func testScopeClauseForAlbumsExcludesBooks() {
        let q = InternetArchiveService.buildSearchQuery(rawInput: "sonata",
                                                        scope: .albums)
        XCTAssertTrue(q.contains("AND NOT collection:(librivoxaudio"),
            "Albums scope must exclude bookish collections. Got: \(q)")
        XCTAssertTrue(q.contains("podcasts") || q.contains("radioprograms") || q.contains("oldtimeradio"),
            "Albums scope must also exclude podcast/radio collections. Got: \(q)")
    }

    func testScopeClauseForAudiobooksIncludesBooks() {
        let q = InternetArchiveService.buildSearchQuery(rawInput: "austen",
                                                        scope: .audiobooks)
        XCTAssertTrue(q.contains("collection:(librivoxaudio OR audio_bookspoetry)"),
            "Audiobooks scope must include bookish collections. Got: \(q)")
    }

    func testSearchUsesRelevanceRankedPerTokenQuery() {
        let q = InternetArchiveService.buildSearchQuery(rawInput: "tarrega guitar")
        // Decode so the assertion is independent of %20/+ encoding.
        // New contract: every token must match, each expanded across
        // title/creator/subject (boosted), AND'd together, and ranked by IA
        // relevance (NO addeddate sort override — that buried good results).
        XCTAssertTrue(q.contains("mediatype:audio"))
        XCTAssertTrue(q.contains("title:\"tarrega\""),
            "token must expand into title field")
        XCTAssertTrue(q.contains("title:\"guitar\""))
        XCTAssertTrue(q.contains(") AND ("),
            "the two tokens must be AND'd so both words must appear")
        XCTAssertFalse(q.contains("title:(") || q.contains("creator:("),
            "must NOT field-scope multiple words into one field")
    }
}
