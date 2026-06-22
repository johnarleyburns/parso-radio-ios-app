import XCTest
@testable import ParsoMusic

@MainActor
final class SearchViewModelTests: XCTestCase {

    // showNoResults drives the "No results" message. It must NOT fire while
    // typing (<2 chars), while searching, on error, or — critically — BEFORE
    // a search has actually completed for the current query (hasSearched gate).
    func testShowNoResultsOnlyAfterAFruitlessQuery() {
        let vm = SearchViewModel()

        vm.query = "a"
        XCTAssertFalse(vm.showNoResults, "too-short query: no message")

        vm.query = "obscure query xyz"
        vm.isSearching = true
        XCTAssertFalse(vm.showNoResults, "while searching: no message")

        // Search finished but the gate is still closed (no completion yet).
        vm.isSearching = false
        vm.results = []
        XCTAssertFalse(vm.showNoResults,
            "results empty but no search has completed → still no message")

        // A completed search with zero results finally shows the message.
        vm.hasSearched = true
        XCTAssertTrue(vm.showNoResults, "completed real query, empty → show message")

        vm.errorMessage = "Search failed — check your connection"
        XCTAssertFalse(vm.showNoResults, "an error shows the error, not 'no results'")

        vm.errorMessage = nil
        vm.results = [SearchViewModel.ResultGroup(
            id: "x", title: "T", creator: "C", addedDate: nil, duration: 0
        )]
        XCTAssertFalse(vm.showNoResults, "with results: no message")
    }

    // Regression: "No results" used to flash during the 400 ms debounce,
    // before the request even went out. Typing a fresh query must re-close
    // the gate so the message disappears until the next response arrives.
    func testNoResultsHiddenWhileQueryPendingSearch() {
        let vm = SearchViewModel()
        vm.query = "beethoven"
        vm.hasSearched = true
        vm.results = []
        XCTAssertTrue(vm.showNoResults, "precondition: a completed empty search")

        // User edits the query — a new search is now pending (debounce).
        vm.query = "beethoven sym"
        vm.searchChanged()
        XCTAssertFalse(vm.hasSearched,
            "a new query must re-close the search-completed gate")
        XCTAssertFalse(vm.showNoResults,
            "no 'No results' while the new query's search is still pending")
    }

    func testShortQueryClearsResults() {
        let vm = SearchViewModel()
        vm.results = [SearchViewModel.ResultGroup(
            id: "x", title: "T", creator: "C", addedDate: nil, duration: 0
        )]
        vm.displayedResults = vm.results
        vm.query = "a"            // < 2 chars
        vm.searchChanged()
        XCTAssertTrue(vm.results.isEmpty, "a <2-char query must clear results")
        XCTAssertTrue(vm.displayedResults.isEmpty, "a <2-char query must clear displayedResults")
    }

    // Item 2: a search ResultGroup carries the IA collection so the row can
    // show it (e.g. "librivoxaudio"). It is optional and defaulted.
    func testResultGroupCarriesCollection() {
        let g = SearchViewModel.ResultGroup(
            id: "x", title: "T", creator: "C", addedDate: nil,
            duration: 0, collection: "librivoxaudio"
        )
        XCTAssertEqual(g.collection, "librivoxaudio")

        let none = SearchViewModel.ResultGroup(
            id: "y", title: "T", creator: "C", addedDate: nil, duration: 0
        )
        XCTAssertNil(none.collection, "collection defaults to nil when absent")
    }

    // Item 6: classification from audio-file count + collection.
    func testClassifyItemKind() {
        XCTAssertEqual(SearchViewModel.classify(audioCount: 1, collection: nil), .track)
        XCTAssertEqual(SearchViewModel.classify(audioCount: 1,
            collection: "librivoxaudio"), .track, "one file is a track even if a book collection")
        XCTAssertEqual(SearchViewModel.classify(audioCount: 12,
            collection: "librivoxaudio"), .book)
        XCTAssertEqual(SearchViewModel.classify(audioCount: 12,
            collection: "audio_bookspoetry"), .book)
        XCTAssertEqual(SearchViewModel.classify(audioCount: 9,
            collection: "opensource_audio"), .album)
        XCTAssertEqual(SearchViewModel.classify(audioCount: 9,
            collection: nil), .album)
    }

    // displayedResults is a @Published stored property that reflects the
    // API insertion order without client-side re-sorting. It starts empty
    // and is set once per page load in performSearch().
    func testDisplayedResultsStartsEmpty() {
        let vm = SearchViewModel()
        XCTAssertTrue(vm.displayedResults.isEmpty)
    }

    // displayedResults must preserve API insertion order. Setting itemKinds
    // must NOT re-sort or reorder the displayed list.
    func testDisplayedResultsPreservesInsertionOrder() {
        let vm = SearchViewModel()
        func g(_ id: String) -> SearchViewModel.ResultGroup {
            .init(id: id, title: id, creator: "c", addedDate: nil, duration: 0)
        }
        vm.results = ["t1", "bk1", "al1", "t2", "bk2", "unk"].map(g)
        vm.displayedResults = vm.results  // simulates performSearch
        vm.itemKinds = [
            "t1": .track, "bk1": .book, "al1": .album,
            "t2": .track, "bk2": .book
        ]
        XCTAssertEqual(vm.displayedResults.map(\.id),
                       ["t1", "bk1", "al1", "t2", "bk2", "unk"],
            "displayedResults must preserve original insertion order regardless of itemKinds")
    }

    // loadNextPage guards: must not fire while a search is already in progress.
    func testLoadNextPageSkippedWhileSearching() async {
        let vm = SearchViewModel()
        vm.isSearching = true
        vm.hasMorePages = true
        // Guard prevents any mutation when isSearching is true.
        await vm.loadNextPage()
        XCTAssertTrue(vm.results.isEmpty,
            "loadNextPage must not mutate state while isSearching")
    }

    func testLoadNextPageSkippedWhenNoMorePages() async {
        let vm = SearchViewModel()
        vm.hasMorePages = false
        await vm.loadNextPage()
        XCTAssertTrue(vm.results.isEmpty,
            "loadNextPage must not mutate state when hasMorePages is false")
    }

    // MARK: - Scope labels

    func testScopeLabelsUpdated() {
        XCTAssertEqual(SearchViewModel.SearchScope.music.label, "Music")
        XCTAssertEqual(SearchViewModel.SearchScope.albums.label, "Albums")
        XCTAssertEqual(SearchViewModel.SearchScope.audiobooks.label, "Audiobooks")
        XCTAssertEqual(SearchViewModel.SearchScope.podcasts.label, "Podcasts")
    }

    // MARK: - Scope filterKind

    func testScopeFilterKind() {
        XCTAssertEqual(SearchViewModel.SearchScope.music.filterKind, .track)
        XCTAssertEqual(SearchViewModel.SearchScope.albums.filterKind, .album)
        XCTAssertEqual(SearchViewModel.SearchScope.audiobooks.filterKind, .book)
        XCTAssertNil(SearchViewModel.SearchScope.podcasts.filterKind)
    }

    // Item 3: history records on successful search, de-dupes case-insensitively,
    // keeps most-recent-first, caps the list, and persists.
    func testSearchHistoryRecordsDedupesAndClears() {
        UserDefaults.standard.removeObject(forKey: "searchHistory")
        let vm = SearchViewModel()
        XCTAssertTrue(vm.recentSearches.isEmpty)

        vm.recordHistory("Bach")
        vm.recordHistory("chopin")
        vm.recordHistory("bach")          // dedupe (case-insensitive)
        XCTAssertEqual(vm.recentSearches, ["bach", "chopin"],
            "most-recent first, de-duped case-insensitively")

        vm.recordHistory("a")             // < 2 chars ignored
        XCTAssertEqual(vm.recentSearches.count, 2)

        vm.removeHistory("chopin")
        XCTAssertEqual(vm.recentSearches, ["bach"])

        // Persisted across instances.
        let vm2 = SearchViewModel()
        XCTAssertEqual(vm2.recentSearches, ["bach"])

        vm.clearHistory()
        XCTAssertTrue(vm.recentSearches.isEmpty)
        XCTAssertNil(UserDefaults.standard.stringArray(forKey: "searchHistory"))
    }

    func testSearchHistoryCapsAtTwelve() {
        UserDefaults.standard.removeObject(forKey: "searchHistory")
        let vm = SearchViewModel()
        for i in 1...20 { vm.recordHistory("query\(i)") }
        XCTAssertEqual(vm.recentSearches.count, 12, "history is capped at 12")
        XCTAssertEqual(vm.recentSearches.first, "query20", "newest first")
    }
}
