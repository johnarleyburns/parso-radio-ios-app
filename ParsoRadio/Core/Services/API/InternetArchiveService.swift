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
        let query = composerQuery(composers: composers)
        return try await search(query: query, confidenceThreshold: 1.5)
    }

    // Musopen items on IA list the performer as creator, not the composer.
    // Composer name typically appears in title or subject, so we search all three.
    func fetchMusopenTracks(composer: String) async throws -> [Track] {
        let rawNames = ComposerMap.aliases.filter { $0.value == composer }.keys.sorted()
        let terms = rawNames.flatMap { name in
            ["creator:\"\(name)\"", "title:\"\(name)\"", "subject:\"\(name)\""]
        }.joined(separator: " OR ")
        let query = "collection:musopen AND (\(terms))"
        return try await search(query: query, musopenCollection: true, confidenceThreshold: 1.5)
    }

    // Tag-only channels (Classical, Ambient): threshold 0.0 because these channels
    // intentionally include composers not in ComposerMap (Beethoven, Mozart, etc.).
    // License filtering happens entirely in mapDoc via LicenseValidator — do NOT
    // put licenseurl wildcards in the Solr query; leading wildcards (*word*) are
    // disabled in Solr by default and cause the whole query to return an error
    // response with no "response" key, making the JSON decode fail.
    func fetchTracks(tags: [String]) async throws -> [Track] {
        let tagClause = tags.map { "subject:\"\($0)\"" }.joined(separator: " OR ")
        let query = "mediatype:audio AND (\(tagClause))"
        return try await search(query: query, confidenceThreshold: 0.0)
    }

    func resolveAudioURL(for identifier: String) async throws -> URL {
        guard let encodedId = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let metaURL = URL(string: "https://archive.org/metadata/\(encodedId)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(from: metaURL)

        struct IAMeta: Decodable {
            struct IAFile: Decodable { let name: String; let format: String? }
            let files: [IAFile]
        }

        let meta = try JSONDecoder().decode(IAMeta.self, from: data)
        let preferredFormats = ["VBR MP3", "128Kbps MP3", "64Kbps MP3", "MP3", "Ogg Vorbis"]
        for format in preferredFormats {
            if let file = meta.files.first(where: { $0.format == format }) {
                let encoded = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.name
                return URL(string: "https://archive.org/download/\(encodedId)/\(encoded)")!
            }
        }
        throw URLError(.unsupportedURL)
    }

    // MARK: - Private

    // Do NOT add a subject filter here — it's inconsistent with InstrumentDetector
    // (which also matches "Brandenburg", "Four Seasons", etc.) and would exclude
    // many valid recordings whose IA subjects use genre tags rather than instrument
    // names. Let InstrumentDetector + channel.matches() classify in code instead.
    private func composerQuery(composers: [String]) -> String {
        let aliases = ComposerMap.aliases
            .filter { composers.contains($0.value) }
            .keys.sorted()
        let creatorClause = aliases.map { "creator:\"\($0)\"" }.joined(separator: " OR ")
        return "mediatype:audio AND (\(creatorClause))"
    }

    private func search(
        query: String,
        musopenCollection: Bool = false,
        confidenceThreshold: Double
    ) async throws -> [Track] {
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
            mapDoc(doc, musopenCollection: musopenCollection, confidenceThreshold: confidenceThreshold)
        }
    }

    private func mapDoc(
        _ doc: IADoc,
        musopenCollection: Bool,
        confidenceThreshold: Double
    ) -> Track? {
        let isMuso = musopenCollection || doc.collection.contains("musopen")

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
            collection: isMuso ? "musopen" : doc.collection.first
        )
        guard license != .rejected else { return nil }

        if !isMuso && confidence < confidenceThreshold { return nil }

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
