import Foundation

extension String {
    var trimmedLowercased: String {
        lowercased().trimmingCharacters(in: .whitespaces)
    }
}
