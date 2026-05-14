import XCTest
@testable import ParsoMusic

final class ComposerMapTests: XCTestCase {

    func testBachVariants() {
        XCTAssertEqual(ComposerMap.normalize("Bach"), "bach")
        XCTAssertEqual(ComposerMap.normalize("J.S. Bach"), "bach")
        XCTAssertEqual(ComposerMap.normalize("Johann Sebastian Bach"), "bach")
        XCTAssertEqual(ComposerMap.normalize("Bach, Johann Sebastian"), "bach")
    }

    func testVivaldiVariants() {
        XCTAssertEqual(ComposerMap.normalize("Vivaldi"), "vivaldi")
        XCTAssertEqual(ComposerMap.normalize("Antonio Vivaldi"), "vivaldi")
        XCTAssertEqual(ComposerMap.normalize("Vivaldi, Antonio"), "vivaldi")
    }

    func testChopinVariants() {
        XCTAssertEqual(ComposerMap.normalize("Chopin"), "chopin")
        XCTAssertEqual(ComposerMap.normalize("Frederic Chopin"), "chopin")
        XCTAssertEqual(ComposerMap.normalize("Frédéric Chopin"), "chopin")
    }

    func testRachmaninoffVariants() {
        XCTAssertEqual(ComposerMap.normalize("Rachmaninoff"), "rachmaninoff")
        XCTAssertEqual(ComposerMap.normalize("Rachmaninov"), "rachmaninoff")
        XCTAssertEqual(ComposerMap.normalize("Sergei Rachmaninoff"), "rachmaninoff")
        XCTAssertEqual(ComposerMap.normalize("Sergei Rachmaninov"), "rachmaninoff")
    }

    func testBeethovenVariants() {
        XCTAssertEqual(ComposerMap.normalize("Beethoven"), "beethoven")
        XCTAssertEqual(ComposerMap.normalize("Ludwig van Beethoven"), "beethoven")
        XCTAssertEqual(ComposerMap.normalize("Beethoven, Ludwig van"), "beethoven")
    }

    func testUnknownReturnsNil() {
        // Use composers not in the map; "scarlatti" and "paganini" are known but unmapped.
        XCTAssertNil(ComposerMap.normalize("Scarlatti"))
        XCTAssertNil(ComposerMap.normalize("Paganini"))
        XCTAssertNil(ComposerMap.normalize(""))
    }

    func testSimilarityMapCoversKnownComposers() {
        XCTAssertNotNil(ComposerMap.similarity["bach"])
        XCTAssertNotNil(ComposerMap.similarity["chopin"])
        XCTAssertTrue(ComposerMap.similarity["bach"]!.contains("vivaldi"))
        XCTAssertTrue(ComposerMap.similarity["chopin"]!.contains("rachmaninoff"))
        XCTAssertNotNil(ComposerMap.similarity["beethoven"])
        XCTAssertTrue(ComposerMap.similarity["tchaikovsky"]!.contains("rachmaninoff"))
    }
}
