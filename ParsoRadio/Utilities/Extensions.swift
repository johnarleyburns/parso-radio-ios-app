import Foundation

extension String {
    var trimmedLowercased: String {
        lowercased().trimmingCharacters(in: .whitespaces)
    }
}

// UC14: shared URLSession with 20 s request timeout for all API services.
// Tests inject a custom session via init(session:) to override this default.
extension URLSession {
    static let app: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
}
