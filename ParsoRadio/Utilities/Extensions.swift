import Foundation

extension String {
    var trimmedLowercased: String {
        lowercased().trimmingCharacters(in: .whitespaces)
    }
}

extension Double {
    var formattedTime: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let t = Int(self)
        let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
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
