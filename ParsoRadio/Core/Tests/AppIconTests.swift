import XCTest
@testable import ParsoRadio

// UC19: verify the compiled asset catalog is present, which confirms AppIcon.appiconset
// was included in the build. UIImage(named:) cannot be used for appiconsets — they are
// system assets compiled into Assets.car for the OS, not runtime-loadable named images.
final class AppIconTests: XCTestCase {
    func testAppIconAssetExistsInBundle() {
        XCTAssertNotNil(
            Bundle.main.url(forResource: "Assets", withExtension: "car"),
            "Assets.car must be present in the app bundle — check AppIcon.appiconset/Contents.json and the 1024×1024 PNG"
        )
    }
}
