import Foundation

struct BookForYouEntry: Codable, Identifiable, Equatable, Sendable {
    let identifier: String
    let title: String
    let author: String
    let subjects: [String]
    let reason: String
    let workKey: String

    var id: String { workKey }

    var coverURL: URL {
        URL(string: "https://archive.org/services/img/\(identifier)")!
    }

    var subjectsString: String {
        subjects.joined(separator: ",")
    }

    init(identifier: String,
         title: String,
         author: String,
         subjects: [String] = [],
         reason: String = "",
         workKey: String) {
        self.identifier = identifier
        self.title = title
        self.author = author
        self.subjects = subjects
        self.reason = reason
        self.workKey = workKey
    }
}
