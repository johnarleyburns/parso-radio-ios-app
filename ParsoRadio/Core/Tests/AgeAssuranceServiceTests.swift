import XCTest
@testable import ParsoMusic

/// Tests the bracket-storage logic and fallback behavior.
/// The DeclaredAgeRange API itself isn't available in the simulator test
/// environment, but the store/restore and bracket derivation paths are.
@MainActor
final class AgeAssuranceServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var service: AgeAssuranceService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = UserDefaults(suiteName: #file)
        defaults.removePersistentDomain(forName: #file)
        service = AgeAssuranceService(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: #file)
        try super.tearDownWithError()
    }

    func test_needsCheck_whenNeverRun() {
        XCTAssertTrue(service.needsCheck,
            "fresh install must need age check")
    }

    func test_defaultBracketIsUnknown() {
        XCTAssertEqual(service.bracket, .unknown,
            "before check, bracket should be unknown")
    }

    func test_requiresKidsMode_whenUnknown() {
        XCTAssertTrue(service.requiresKidsMode,
            "unknown bracket → safety first → requires Kids Mode")
    }

    func test_requiresKidsMode_whenChild() {
        service.overrideToTeen()  // sets to .teen
        XCTAssertFalse(service.requiresKidsMode,
            "teen bracket → does NOT require forced Kids Mode")
    }

    func test_isChild_falseForUnknown() {
        XCTAssertFalse(service.isChild,
            "unknown is not child (it's a separate fallback)")
    }

    func test_overrideToTeen_setsTeenAndCompletes() {
        service.overrideToTeen()
        XCTAssertEqual(service.bracket, .teen)
        XCTAssertFalse(service.needsCheck)
        XCTAssertFalse(service.requiresKidsMode)
        XCTAssertFalse(service.isChild)
    }

    func test_requiresTrackingDisabled_whenTeen() {
        service.overrideToTeen()
        XCTAssertTrue(service.requiresTrackingDisabled,
            "teen bracket should require tracking disabled per minor-protection laws")
    }

    func test_requiresTrackingDisabled_falseForUnknown() {
        // Unknown bracket enters Kids Mode, which already has no tracking
        XCTAssertFalse(service.requiresTrackingDisabled,
            "unknown is handled by Kids Mode, not the tracking flag")
    }

    func test_persistedResultSurvivesNewInstance() {
        service.overrideToTeen()
        // Create a brand-new service against the same UserDefaults
        let second = AgeAssuranceService(defaults: defaults)
        XCTAssertEqual(second.bracket, .teen,
            "persisted bracket should survive instance recreate")
        XCTAssertFalse(second.needsCheck,
            "completed flag should be persisted")
    }

    func test_testSet_clearsState() {
        service.overrideToTeen()
        service._testSet(checkDone: false)
        XCTAssertTrue(service.needsCheck, "_testSet should clear completed flag")
        XCTAssertEqual(service.bracket, .unknown, "bracket should reset to unknown")
    }
}
