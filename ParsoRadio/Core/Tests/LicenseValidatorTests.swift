import XCTest
@testable import ParsoRadio

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

    func testCCBySAIsRejected() {
        XCTAssertEqual(
            validator.validate(licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/", year: nil, collection: nil),
            .rejected
        )
    }

    func testCCByNCIsRejected() {
        XCTAssertEqual(
            validator.validate(licenseURL: "https://creativecommons.org/licenses/by-nc/4.0/", year: nil, collection: nil),
            .rejected
        )
    }

    func testNilURLAndNilYearIsRejected() {
        XCTAssertEqual(validator.validate(licenseURL: nil, year: nil, collection: nil), .rejected)
    }

    func testMusopenTakesPriorityOverYear() {
        XCTAssertEqual(validator.validate(licenseURL: nil, year: 1800, collection: "musopen"), .cc0)
    }
}
