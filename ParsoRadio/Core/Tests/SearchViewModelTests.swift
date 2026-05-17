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
        vm.query = "a"            // < 2 chars
        vm.searchChanged()
        XCTAssertTrue(vm.results.isEmpty, "a <2-char query must clear results")
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
}
