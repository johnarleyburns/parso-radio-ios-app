import XCTest
@testable import ParsoMusic

final class WorkKeyTests: XCTestCase {

    func testWorkKeyCollapsesVersionSuffix() {
        let a = WorkKey.normalized(author: "Mary Shelley", title: "Frankenstein")
        let b = WorkKey.normalized(author: "Mary Shelley", title: "Frankenstein (version 2)")
        XCTAssertEqual(a, b, "Version suffixes must collapse onto the same work key")
    }

    func testWorkKeyCollapsesReaderSuffix() {
        let a = WorkKey.normalized(author: "H. G. Wells", title: "The Time Machine")
        let b = WorkKey.normalized(author: "H. G. Wells", title: "The Time Machine (read by Mark Nelson)")
        XCTAssertEqual(a, b)
    }

    func testCleanTitleStripsParentheticals() {
        XCTAssertEqual(WorkKey.cleanTitle("Dracula (version 2)"), "dracula")
        XCTAssertEqual(WorkKey.cleanTitle("The Time Machine (read by Mark Nelson)"), "the time machine")
    }

    func testWorkKeyNormalizesWhitespaceAndCase() {
        let key = WorkKey.normalized(author: "  Mary   Shelley  ", title: "Frankenstein  ")
        XCTAssertEqual(key, "mary shelley\u{00B7}frankenstein")
    }

    func testDifferentWorksDiffer() {
        let a = WorkKey.normalized(author: "Jane Austen", title: "Pride and Prejudice")
        let b = WorkKey.normalized(author: "Herman Melville", title: "Moby Dick")
        XCTAssertNotEqual(a, b)
    }
}
