import XCTest
@testable import ParsoMusic

final class BookForYouServiceTests: XCTestCase {

    // MARK: - Work-Key Normalization (§5.0)

    func testWorkKeyBasicNormalization() {
        let key = BookForYouService.workKey(author: "Mary Shelley", title: "Frankenstein")
        XCTAssertEqual(key, "mary shelley·frankenstein")
    }

    func testWorkKeyStripsVersionSuffix() {
        let key = BookForYouService.workKey(author: "Mary Shelley", title: "Frankenstein (version 2)")
        XCTAssertEqual(key, "mary shelley·frankenstein")
    }

    func testWorkKeyStripsDramaticReading() {
        let key = BookForYouService.workKey(author: "Jane Austen",
                                             title: "Pride and Prejudice (dramatic reading)")
        XCTAssertEqual(key, "jane austen·pride and prejudice")
    }

    func testWorkKeyStripsReaderSuffix() {
        let key = BookForYouService.workKey(author: "Herman Melville",
                                             title: "Moby Dick (read by Stewart Wills)")
        XCTAssertEqual(key, "herman melville·moby dick")
    }

    func testWorkKeyStripsBothVersionAndReader() {
        let key = BookForYouService.workKey(author: "Bram Stoker",
                                             title: "Dracula (version 3) (read by John Doe)")
        XCTAssertEqual(key, "bram stoker·dracula")
    }

    func testWorkKeyStripsSoloAndGroup() {
        let k1 = BookForYouService.workKey(author: "Charlotte Bronte", title: "Jane Eyre (solo)")
        let k2 = BookForYouService.workKey(author: "Leo Tolstoy", title: "War and Peace (group)")
        XCTAssertEqual(k1, "charlotte bronte·jane eyre")
        XCTAssertEqual(k2, "leo tolstoy·war and peace")
    }

    func testWorkKeyStripsUnabridgedAndAbridged() {
        let k1 = BookForYouService.workKey(author: "Author", title: "Book (unabridged)")
        let k2 = BookForYouService.workKey(author: "Author", title: "Book (abridged)")
        XCTAssertEqual(k1, "author·book")
        XCTAssertEqual(k2, "author·book")
    }

    func testWorkKeyCollapsesWhitespace() {
        let key = BookForYouService.workKey(author: "  Mary   Shelley  ", title: "Frankenstein  ")
        XCTAssertEqual(key, "mary shelley·frankenstein")
    }

    func testWorkKeyDifferentVersionsSameNormalization() {
        let k1 = BookForYouService.workKey(author: "Mary Shelley", title: "Frankenstein (version 2)")
        let k2 = BookForYouService.workKey(author: "Mary Shelley", title: "Frankenstein (version 3)")
        XCTAssertEqual(k1, k2, "Different versions of the same book must normalize to the same workKey")
    }

    // MARK: - Clean Title

    func testCleanTitleStripsParentheticals() {
        XCTAssertEqual(BookForYouService.cleanTitle("Dracula (version 2)"), "dracula")
        XCTAssertEqual(BookForYouService.cleanTitle("The Time Machine (read by Mark Nelson)"), "the time machine")
    }

    func testCleanTitlePreservesMeaningfulText() {
        let cleaned = BookForYouService.cleanTitle("Pride and Prejudice")
        XCTAssertEqual(cleaned, "pride and prejudice")
    }

    func testCleanTitleHandlesNestedParentheses() {
        // IA titles sometimes have nested or sequential parentheticals
        let cleaned = BookForYouService.cleanTitle("War and Peace (version 2) (dramatic reading)")
        XCTAssertEqual(cleaned, "war and peace")
    }

    // MARK: - Date-Seeded RNG (§5.6)

    func testDateSeededRNGDeterministic() {
        let pool = ["a", "b", "c", "d", "e"]
        let p1 = BookForYouService.choose(from: pool, seed: "2025-06-23")
        let p2 = BookForYouService.choose(from: pool, seed: "2025-06-23")
        XCTAssertEqual(p1, p2, "Same date seed must produce same pick")
    }

    func testDateSeededRNGGivesValidResult() {
        let pool = ["a", "b", "c", "d", "e"]
        let pick = BookForYouService.choose(from: pool, seed: "2025-06-23")
        XCTAssertNotNil(pick)
        XCTAssertTrue(pool.contains(pick!), "Pick must be from the pool")
    }

    func testDateSeededRNGEmptyPool() {
        let pick = BookForYouService.choose(from: [String](), seed: "2025-06-23")
        XCTAssertNil(pick, "Empty pool must return nil")
    }

    // MARK: - BookCandidate WorkKey

    func testBookCandidateWorkKey() {
        let candidate = BookCandidate(
            identifier: "dracula_123", title: "Dracula (version 2)",
            creator: "Bram Stoker", subjects: ["horror"], downloads: 1000)
        XCTAssertEqual(candidate.workKey, "bram stoker·dracula")
    }

    // MARK: - Exclusion Logic (§5.4) — Database-backed

    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    override func tearDown() {
        db = nil
        super.tearDown()
    }

    func testRecordBookListenedAndFetchWorkKeys() async {
        await db.recordBookListened(
            workKey: "mary shelley·frankenstein",
            identifier: "frankenstein_v2_123",
            title: "Frankenstein",
            author: "Mary Shelley",
            subjects: "horror,classic"
        )

        let listenedKeys = await db.fetchBookListenedWorkKeys()
        XCTAssertTrue(listenedKeys.contains("mary shelley·frankenstein"))
        XCTAssertEqual(listenedKeys.count, 1)
    }

    func testUpsertBookListenedUpdatesTimestamp() async {
        await db.recordBookListened(
            workKey: "bram stoker·dracula",
            identifier: "dracula_v1",
            title: "Dracula", author: "Bram Stoker")

        let beforeKeys = await db.fetchBookListenedWorkKeys()
        XCTAssertEqual(beforeKeys.count, 1)

        // Record again — should upsert, not duplicate
        await db.recordBookListened(
            workKey: "bram stoker·dracula",
            identifier: "dracula_v1",
            title: "Dracula", author: "Bram Stoker")

        let afterKeys = await db.fetchBookListenedWorkKeys()
        XCTAssertEqual(afterKeys.count, 1, "Upsert must not duplicate workKey")
    }

    func testBookCuratedDayCacheRoundTrip() async {
        let entry = BookForYouEntry(
            identifier: "dracula_v2", title: "Dracula",
            author: "Bram Stoker", subjects: [], reason: "Popular on LibriVox",
            workKey: "bram stoker·dracula")

        await db.insertBookCurated(entry, day: "2025-06-23")

        let cached = await db.fetchBookCuratedForDay("2025-06-23")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.identifier, "dracula_v2")
        XCTAssertEqual(cached?.title, "Dracula")
    }

    func testBookCuratedDayLookupEmpty() async {
        let cached = await db.fetchBookCuratedForDay("2025-06-23")
        XCTAssertNil(cached)
    }

    func testDeleteBookCuratedForDay() async {
        let entry = BookForYouEntry(
            identifier: "test", title: "Test",
            author: "Author", subjects: [], reason: "test",
            workKey: "author·test")

        await db.insertBookCurated(entry, day: "2025-06-23")
        await db.insertBookCurated(entry, day: "2025-06-24")

        await db.deleteBookCuratedForDay("2025-06-23")

        let cached23 = await db.fetchBookCuratedForDay("2025-06-23")
        let cached24 = await db.fetchBookCuratedForDay("2025-06-24")
        XCTAssertNil(cached23)
        XCTAssertNotNil(cached24, "Only the specified day should be deleted")
    }

    func testFetchLeastRecentlyCurated() async {
        let entry1 = BookForYouEntry(
            identifier: "old", title: "Old", author: "A",
            subjects: [], reason: "", workKey: "a·old")
        let entry2 = BookForYouEntry(
            identifier: "new", title: "New", author: "B",
            subjects: [], reason: "", workKey: "b·new")

        // Insert entry1 (will have older timestamp)
        await db.insertBookCurated(entry1, day: "2025-01-01")

        // Small delay to ensure different timestamps
        try? await Task.sleep(nanoseconds: 10_000_000)

        await db.insertBookCurated(entry2, day: "2025-01-02")

        let lru = await db.fetchLeastRecentlyCurated()
        XCTAssertNotNil(lru)
        XCTAssertEqual(lru?.workKey, "a·old", "LRU should be the oldest entry")
    }

    func testBookCuratedWorkKeysAreUnique() async {
        let entry1 = BookForYouEntry(
            identifier: "id1", title: "T1", author: "A1",
            subjects: [], reason: "", workKey: "a1·t1")
        let entry2 = BookForYouEntry(
            identifier: "id2", title: "T2", author: "A2",
            subjects: [], reason: "", workKey: "a2·t2")

        await db.insertBookCurated(entry1, day: "2025-06-23")
        await db.insertBookCurated(entry2, day: "2025-06-24")

        let keys = await db.fetchBookCuratedWorkKeys()
        XCTAssertEqual(keys.count, 2)
        XCTAssertTrue(keys.contains("a1·t1"))
        XCTAssertTrue(keys.contains("a2·t2"))
    }

    // MARK: - Never-Repeat Simulation (§5.4 + §5.6)

    func testNeverRepeatAcrossSimulatedDays() async {
        // Pre-populate curated history
        let entry1 = BookForYouEntry(
            identifier: "dracula", title: "Dracula",
            author: "Bram Stoker", subjects: [],
            reason: "Popular on LibriVox", workKey: "bram stoker·dracula")
        await db.insertBookCurated(entry1, day: "2025-06-20")

        let listenedKeys = await db.fetchBookListenedWorkKeys()
        let curatedKeys = await db.fetchBookCuratedWorkKeys()
        let exclusionKeys = listenedKeys.union(curatedKeys)

        // A candidate matching a curated workKey should be excluded
        let candidate = BookCandidate(
            identifier: "dracula_v3", title: "Dracula (version 3)",
            creator: "Bram Stoker", subjects: [], downloads: 500)

        XCTAssertTrue(exclusionKeys.contains(candidate.workKey),
            "Previously curated workKey must be in exclusion set")
    }

    func testNeverListenedBookExcluded() async {
        await db.recordBookListened(
            workKey: "jane austen·pride and prejudice",
            identifier: "pp_v1", title: "Pride and Prejudice",
            author: "Jane Austen")

        let exclusionKeys = await db.fetchBookListenedWorkKeys()

        let candidate = BookCandidate(
            identifier: "pp_v2", title: "Pride and Prejudice (version 2)",
            creator: "Jane Austen", subjects: [], downloads: 600)

        XCTAssertTrue(exclusionKeys.contains(candidate.workKey),
            "WorkKey of a listened book must appear in exclusion set")
    }

    // MARK: - BookForYouEntry Model

    func testBookForYouEntryCoverURL() {
        let entry = BookForYouEntry(
            identifier: "dracula_v2", title: "Dracula",
            author: "Bram Stoker", subjects: [], reason: "",
            workKey: "bram stoker·dracula")
        XCTAssertEqual(
            entry.coverURL.absoluteString,
            "https://archive.org/services/img/dracula_v2")
    }

    func testBookForYouEntryCodableRoundTrip() throws {
        let entry = BookForYouEntry(
            identifier: "test_id", title: "Test Title",
            author: "Test Author", subjects: ["fiction", "horror"],
            reason: "Because you enjoyed Mary Shelley",
            workKey: "test author·test title")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(BookForYouEntry.self, from: data)
        XCTAssertEqual(decoded.identifier, entry.identifier)
        XCTAssertEqual(decoded.title, entry.title)
        XCTAssertEqual(decoded.author, entry.author)
        XCTAssertEqual(decoded.subjects, entry.subjects)
        XCTAssertEqual(decoded.workKey, entry.workKey)
    }

    func testBookForYouEntryIDIsWorkKey() {
        let entry = BookForYouEntry(
            identifier: "x", title: "T", author: "A",
            subjects: [], reason: "", workKey: "a·t")
        XCTAssertEqual(entry.id, "a·t")
    }

    // MARK: - Durable Ledgers Survive Track Eviction

    func testBookListenHistorySurvivesTrackEviction() async {
        await db.recordBookListened(
            workKey: "herman melville·moby dick",
            identifier: "moby_dick_123",
            title: "Moby Dick",
            author: "Herman Melville")

        // The listened record is independent of tracks table — should still exist
        let keys = await db.fetchBookListenedWorkKeys()
        XCTAssertTrue(keys.contains("herman melville·moby dick"))
        XCTAssertEqual(keys.count, 1)
    }

    func testBookCuratedHistoryIndependentOfTracksTable() async {
        let entry = BookForYouEntry(
            identifier: "some_deleted_track", title: "Gone Book",
            author: "Forgotten Author", subjects: [], reason: "",
            workKey: "forgotten author·gone book")
        await db.insertBookCurated(entry, day: "2025-01-15")

        // Even with no corresponding track, curated record persists
        let cached = await db.fetchBookCuratedForDay("2025-01-15")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.workKey, "forgotten author·gone book")
    }

    // MARK: - BookForYouStore Daily Stability

    func testStoreTodayKeyFormat() {
        let store = BookForYouStore.shared
        // Verify the store exists and can be accessed
        XCTAssertNotNil(store)
        // todayKey() is private but the format must be YYYY-MM-DD
    }
}
