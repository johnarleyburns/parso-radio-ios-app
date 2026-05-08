import XCTest
import UIKit
@testable import ParsoRadio

// UC19: verify the app icon asset is present and non-corrupt in the bundle.
// Runs within the app's test host so the asset catalog is accessible.
final class AppIconTests: XCTestCase {
    func testAppIconAssetExistsInBundle() {
        XCTAssertNotNil(
            UIImage(named: "AppIcon"),
            "AppIcon must be present in the app bundle — check AppIcon.appiconset/Contents.json and the 1024×1024 PNG"
        )
    }
}
