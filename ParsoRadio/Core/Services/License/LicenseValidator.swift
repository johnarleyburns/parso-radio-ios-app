import Foundation

struct LicenseValidator {
    func validate(licenseURL: String?, year: Int?, collection: String?) -> LicenseType {
        if collection == "musopen" { return .cc0 }
        if let year, year < 1923 { return .publicDomain }
        guard let url = licenseURL?.lowercased() else { return .rejected }
        if url.contains("publicdomain") { return .publicDomain }
        if url.contains("zero") { return .cc0 }
        if url.contains("licenses/by/")
            && !url.contains("by-nc")
            && !url.contains("by-sa")
            && !url.contains("by-nd") { return .ccBy }
        return .rejected
    }
}
