import XCTest
@testable import ParsoMusic

final class LicenseValidatorTests: XCTestCase {
    private let validator = LicenseValidator()

    func testMusopenCollectionIsCC0() {
        XCTAssertEqual(validator.validate(licenseURL: nil, year: nil, collection: "musopen"), .cc0)
    }

    func testPre1923IsPublicDomain() {
        XCTAssertEqual(validator.validate(licenseURL: nil, year: 1900, collection: nil), .publicDomain)
        XCTAssertEqual(validator.validate(licenseURL: nil, year: 1922, collection: nil), .publicDomain)
    }

    func testExactly1923IsRejected() {
        XCTAssertEqual(validator.validate(licenseURL: nil, year: 1923, collection: nil), .rejected)
    }

    func testPublicDomainURL() {
        XCTAssertEqual(
            validator.validate(licenseURL: "https://creativecommons.org/publicdomain/mark/1.0/", year: nil, collection: nil),
            .publicDomain
        )
    }

    func testCC0URL() {
        XCTAssertEqual(
            validator.validate(licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/", year: nil, collection: nil),
            .cc0
        )
    }

    func testCCByURL() {
        XCTAssertEqual(
            validator.validate(licenseURL: "https://creativecommons.org/licenses/by/4.0/", year: nil, collection: nil),
            .ccBy
        )
    }

    func testCCBySAIsAccepted() {
        // BY-SA is accepted: app is non-commercial so share-alike doesn't restrict us.
        XCTAssertEqual(
            validator.validate(licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/", year: nil, collection: nil),
            .ccBy
        )
    }

    func testCCByNCIsAccepted() {
        // BY-NC is accepted: the app is non-commercial so the NC clause doesn't restrict us.
        XCTAssertEqual(
            validator.validate(licenseURL: "https://creativecommons.org/licenses/by-nc/4.0/", year: nil, collection: nil),
            .ccBy
        )
    }

    func testNilURLAndNilYearIsRejected() {
        XCTAssertEqual(validator.validate(licenseURL: nil, year: nil, collection: nil), .rejected)
    }

    func testMusopenTakesPriorityOverYear() {
        XCTAssertEqual(validator.validate(licenseURL: nil, year: 1800, collection: "musopen"), .cc0)
    }
}
