import Foundation

struct InternetArchiveService {
    func fetchTracks(composers: [String], instruments: [String]) async throws -> [Track] { [] }
    func fetchMusopenTracks(composer: String) async throws -> [Track] { [] }
    func fetchTracks(tags: [String]) async throws -> [Track] { [] }
}
