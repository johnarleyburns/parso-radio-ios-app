import Foundation

struct InternetArchiveService {
    private let session: URLSession
    private let normalizer = MetadataNormalizer()
    private let validator = LicenseValidator()

    static let searchBase = "https://archive.org/advancedsearch.php"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchTracks(composers: [String], instruments: [String]) async throws -> [Track] {
        let query = composerQuery(composers: composers, instruments: instruments)
        return try await search(query: query)
    }

    func fetchMusopenTracks(composer: String) async throws -> [Track] {
        let rawNames = ComposerMap.aliases.filter { $0.value == composer }.keys.sorted()
        let creatorClause = rawNames.map { "creator:\"\($0)\"" }.joined(separator: " OR ")
        let query = "collection:musopen AND (\(creatorClause))"
        return try await search(query: query, musopenCollection: true)
    }

    func fetchTracks(tags: [String]) async throws -> [Track] {
        let tagClause = tags.map { "subject:\"\($0)\"" }.joined(separator: " OR ")
        let licenseClause = "(licenseurl:*publicdomain* OR licenseurl:*zero* OR licenseurl:*licenses/by/*)"
        let query = "mediatype:audio AND (\(tagClause)) AND \(licenseClause)"
        return try await search(query: query)
    }

    // MARK: - Private

    private func composerQuery(composers: [String], instruments: [String]) -> String {
        let aliases = ComposerMap.aliases
            .filter { composers.contains($0.value) }
            .keys.sorted()
        let creatorClause = aliases.map { "creator:\"\($0)\"" }.joined(separator: " OR ")

        var q = "mediatype:audio AND (\(creatorClause))"

        if !instruments.isEmpty {
            let keywords = instruments.flatMap { instrumentKeywords(for: $0) }
            let subjectClause = keywords.map { "subject:\"\($0)\"" }.joined(separator: " OR ")
            q += " AND (\(subjectClause))"
        }

        q += " AND (licenseurl:*publicdomain* OR licenseurl:*zero* OR licenseurl:*licenses/by/*)"
        return q
    }

    private func instrumentKeywords(for instrument: String) -> [String] {
        switch instrument {
        case "strings": return ["violin", "cello", "viola", "strings", "string quartet"]
        case "piano":   return ["piano", "pianoforte"]
        default:        return [instrument]
        }
    }

    private func search(query: String, musopenCollection: Bool = false) async throws -> [Track] {
        var components = URLComponents(string: Self.searchBase)!
        components.queryItems = [
            URLQueryItem(name: "q",       value: query),
            URLQueryItem(name: "fl[]",    value: "identifier"),
            URLQueryItem(name: "fl[]",    value: "title"),
            URLQueryItem(name: "fl[]",    value: "creator"),
            URLQueryItem(name: "fl[]",    value: "subject"),
            URLQueryItem(name: "fl[]",    value: "licenseurl"),
            URLQueryItem(name: "fl[]",    value: "description"),
            URLQueryItem(name: "fl[]",    value: "year"),
            URLQueryItem(name: "fl[]",    value: "collection"),
            URLQueryItem(name: "output",  value: "json"),
            URLQueryItem(name: "rows",    value: "100"),
            URLQueryItem(name: "sort[]",  value: "downloads desc"),
        ]

        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(IASearchResponse.self, from: data)

        return response.response.docs.compactMap { doc in
            mapDoc(doc, musopenCollection: musopenCollection)
        }
    }

    private func mapDoc(_ doc: IADoc, musopenCollection: Bool) -> Track? {
        let collectionFirst = doc.collection.first
        let isMuso = musopenCollection || collectionFirst == "musopen"

        let (composer, instruments, confidence) = normalizer.normalize(
            creator: doc.creator,
            title: doc.title,
            subjects: doc.subjects,
            description: doc.description,
            licenseURL: doc.licenseurl,
            year: doc.year,
            duration: nil
        )

        let license = validator.validate(
            licenseURL: doc.licenseurl,
            year: doc.year,
            collection: isMuso ? "musopen" : collectionFirst
        )
        guard license != .rejected else { return nil }

        // Tracks going into composer channels need confidence ≥ 1.5
        // (Musopen tracks are pre-qualified and skip the threshold)
        if !isMuso && confidence < 1.5 { return nil }

        let streamURL = URL(string: "https://archive.org/download/\(doc.identifier)")!

        return Track(
            id: doc.identifier,
            source: "internet_archive",
            title: doc.title ?? doc.identifier,
            artist: doc.creator ?? "Unknown",
            duration: 0,
            streamURL: streamURL,
            downloadURL: streamURL,
            localFilePath: nil,
            license: license,
            tags: doc.subjects,
            qualityScore: min(confidence / 4.0, 1.0),
            rawCreator: doc.creator ?? "",
            composer: composer,
            instruments: instruments,
            metadataConfidence: confidence
        )
    }
}

// MARK: - Decodable response types

struct IASearchResponse: Decodable {
    let response: IAResponseBody
}

struct IAResponseBody: Decodable {
    let docs: [IADoc]
}

struct IADoc: Decodable {
    let identifier: String
    let title: String?
    let creator: String?
    let subjects: [String]
    let licenseurl: String?
    let description: String?
    let year: Int?
    let collection: [String]

    enum CodingKeys: String, CodingKey {
        case identifier, title, creator, licenseurl, description, year
        case subject, collection
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier  = try c.decode(String.self, forKey: .identifier)
        title       = try? c.decode(String.self, forKey: .title)
        licenseurl  = try? c.decode(String.self, forKey: .licenseurl)
        description = try? c.decode(String.self, forKey: .description)

        // creator: String or [String]
        if let arr = try? c.decode([String].self, forKey: .creator) {
            creator = arr.first
        } else {
            creator = try? c.decode(String.self, forKey: .creator)
        }

        // subject: String or [String]
        if let arr = try? c.decode([String].self, forKey: .subject) {
            subjects = arr
        } else if let s = try? c.decode(String.self, forKey: .subject) {
            subjects = [s]
        } else {
            subjects = []
        }

        // year: Int or String
        if let y = try? c.decode(Int.self, forKey: .year) {
            year = y
        } else if let s = try? c.decode(String.self, forKey: .year), let y = Int(s) {
            year = y
        } else {
            year = nil
        }

        // collection: String or [String]
        if let arr = try? c.decode([String].self, forKey: .collection) {
            collection = arr
        } else if let s = try? c.decode(String.self, forKey: .collection) {
            collection = [s]
        } else {
            collection = []
        }
    }
}
