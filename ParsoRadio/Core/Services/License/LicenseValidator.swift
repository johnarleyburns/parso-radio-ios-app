import Foundation

struct LicenseValidator {
    func validate(licenseURL: String?, year: Int?, collection: String?) -> LicenseType {
        if collection == "musopen" { return .cc0 }
        if let year, year < 1923 { return .publicDomain }
        guard let url = licenseURL?.lowercased() else { return .rejected }
        if url.contains("zero") { return .cc0 }
        if url.contains("publicdomain") { return .publicDomain }
        // Accept all CC BY variants (BY, BY-SA, BY-NC, BY-NC-SA); app is non-commercial so NC/SA are fine.
        if url.contains("licenses/by") { return .ccBy }
        return .rejected
    }
}
