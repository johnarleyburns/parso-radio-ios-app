import XCTest
@testable import ParsoMusic

@MainActor
final class OnboardingTasteTests: XCTestCase {

    func testChipListIsNotEmpty() {
        XCTAssertFalse(OnboardingChip.all.isEmpty)
        XCTAssertEqual(OnboardingChip.all.count, 10, "expected 10 onboarding chips")
    }

    func testChipIDsAreUnique() {
        let ids = OnboardingChip.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "chip IDs must be unique")
    }

    func testChipsHaveValidCollectionIDs() {
        for chip in OnboardingChip.all {
            for collectionID in chip.collectionIDs {
                XCTAssertFalse(collectionID.isEmpty, "chip \(chip.id) has empty collection ID")
            }
        }
    }

    func testPianoChipHasCorrectMapping() {
        let piano = OnboardingChip.all.first { $0.id == "piano" }
        XCTAssertNotNil(piano)
        XCTAssertTrue(piano!.collectionIDs.contains("tedjonespiano"),
                       "piano chip should seed tedjonespiano")
        XCTAssertEqual(piano!.subjectSeed, "piano")
    }

    func testBachChipHasCreatorSeed() {
        let bach = OnboardingChip.all.first { $0.id == "bach" }
        XCTAssertNotNil(bach)
        XCTAssertEqual(bach!.subjectSeed, "classical")
        XCTAssertNotNil(bach!.creatorSeed)
    }

    func testJazzChipHasMultipleCollections() {
        let jazz = OnboardingChip.all.first { $0.id == "jazz" }
        XCTAssertNotNil(jazz)
        XCTAssertTrue(jazz!.collectionIDs.count >= 2,
                       "jazz chip should seed multiple collections")
    }

    func testAllChipsHaveLabelsAndIcons() {
        for chip in OnboardingChip.all {
            XCTAssertFalse(chip.label.isEmpty, "chip \(chip.id) has empty label")
            XCTAssertFalse(chip.icon.isEmpty, "chip \(chip.id) has empty icon")
        }
    }

    func testSeedWeightConstant() {
        XCTAssertGreaterThan(RecommendationConstants.onboardingSeedWeight, 1.0,
                              "onboarding seed weight should be > 1x a plain play")
        XCTAssertLessThan(RecommendationConstants.onboardingSeedWeight, 3.0,
                           "onboarding seed weight should be < 3x to allow natural overtaking")
    }

    func testAllChipsProduceTasteSignals() {
        for chip in OnboardingChip.all {
            let hasCollections = !chip.collectionIDs.isEmpty
            let hasSubject = chip.subjectSeed != nil && !chip.subjectSeed!.isEmpty
            let hasCreator = chip.creatorSeed != nil
            XCTAssertTrue(hasCollections || hasSubject || hasCreator,
                           "chip \(chip.id) produces no taste signal for MadeForYou")
        }
    }
}
