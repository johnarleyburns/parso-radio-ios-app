import XCTest
@testable import ParsoMusic

@MainActor
final class SearchViewModelTests: XCTestCase {

    // showNoResults drives the "No results" message — it must NOT fire while
    // typing (<2 chars), while searching, or when there's an error.
    func testShowNoResultsOnlyAfterAFruitlessQuery() {
        let vm = SearchViewModel()

        vm.query = "a"
        XCTAssertFalse(vm.showNoResults, "too-short query: no message")

        vm.query = "obscure query xyz"
        vm.isSearching = true
        XCTAssertFalse(vm.showNoResults, "while searching: no message")

        vm.isSearching = false
        vm.results = []
        XCTAssertTrue(vm.showNoResults, "real query, done, empty → show message")

        vm.errorMessage = "Search failed — check your connection"
        XCTAssertFalse(vm.showNoResults, "an error shows the error, not 'no results'")

        vm.errorMessage = nil
        vm.results = [SearchViewModel.ResultGroup(
            id: "x", title: "T", creator: "C", addedDate: nil, duration: 0
        )]
        XCTAssertFalse(vm.showNoResults, "with results: no message")
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
}
