import Foundation

struct InternetArchiveService {
    private let session: URLSession
    private let normalizer = MetadataNormalizer()
    private let validator = LicenseValidator()

    static let searchBase = "https://archive.org/advancedsearch.php"

    init(session: URLSession = .app) {
        self.session = session
    }

    // MARK: - Date parsing

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Basic = ISO8601DateFormatter()
    // IA Solr returns dates without timezone (e.g. "2023-08-15T14:30:00.000000") — treat as UTC.
    private static let iaFractionalNoTZ: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private static let iaBasicNoTZ: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func parseIADate(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        return iso8601WithFractional.date(from: str)
            ?? iso8601Basic.date(from: str)
            ?? iaFractionalNoTZ.date(from: str)
            ?? iaBasicNoTZ.date(from: str)
    }

    private static let ymdNoTZ: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // IA `date` can be ISO, "yyyy-MM-dd", or just "yyyy"; fall back to `year`.
    private static func parseRecordingDate(_ str: String?, year: Int?) -> Date? {
        if let str, !str.isEmpty {
            if let d = parseIADate(str) ?? ymdNoTZ.date(from: str) { return d }
            if str.count >= 4, let y = Int(str.prefix(4)) {
                return DateComponents(calendar: .current, year: y, month: 1, day: 1).date
            }
        }
        if let year { return DateComponents(calendar: .current, year: year, month: 1, day: 1).date }
        return nil
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

    // Pure-Lucene registry channels: the single ia_queries.json query is the
    // ONLY curation. NOTHING is filtered in code — no LicenseValidator
    // rejection, no MetadataNormalizer/confidence gate, no collection/category
    // post-filter. Every document the query returns becomes a track. matchTags
    // are STAMPED onto every track so Channel.matches() can isolate them in the
    // shared DB regardless of how sparse the IA item's subject metadata is
    // (many curated results match by creator and carry no useful subject).
    func fetchTracks(iaQuery: String, matchTags: [String] = []) async throws -> [Track] {
        var components = URLComponents(string: Self.searchBase)!
        components.queryItems = [
            URLQueryItem(name: "q",      value: iaQuery),
            URLQueryItem(name: "fl[]",   value: "identifier"),
            URLQueryItem(name: "fl[]",   value: "title"),
            URLQueryItem(name: "fl[]",   value: "creator"),
            URLQueryItem(name: "fl[]",   value: "subject"),
            URLQueryItem(name: "fl[]",   value: "licenseurl"),
            URLQueryItem(name: "fl[]",   value: "year"),
            URLQueryItem(name: "fl[]",   value: "collection"),
            URLQueryItem(name: "fl[]",   value: "addeddate"),
            URLQueryItem(name: "fl[]",   value: "date"),
            URLQueryItem(name: "fl[]",   value: "downloads"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "rows",   value: "200"),
            // Sort by download count to approximate popularity.
            URLQueryItem(name: "sort[]", value: "downloads desc"),
        ]
        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(IASearchResponse.self, from: data)

        return response.response.docs.compactMap { doc -> Track? in
            let encodedId = doc.identifier
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doc.identifier
            // The only thing that can drop a doc is an unconstructable URL
            // (a track with no URL is unplayable) — that is not content
            // filtering, just a safety guard.
            guard let streamURL = URL(string: "https://archive.org/download/\(encodedId)")
            else { return nil }
            // license is computed for the UI badge only; it never rejects.
            let license = validator.validate(
                licenseURL: doc.licenseurl, year: doc.year, collection: doc.collection.first
            )
            var t = Track(
                id: doc.identifier,
                source: "internet_archive",
                title: doc.title ?? doc.identifier,
                artist: doc.creator ?? "Unknown",
                duration: 0,
                streamURL: streamURL,
                downloadURL: streamURL,
                localFilePath: nil,
                license: license,
                tags: doc.subjects.map { $0.lowercased() },
                // Popularity-as-quality: down-weight low-download (amateur)
                // items so the channel's well-loved recordings surface more
                // (QueueManager.selectionWeight multiplies by qualityScore).
                qualityScore: IAQualityScore.fromDownloads(doc.downloads),
                rawCreator: doc.creator ?? "",
                composer: nil,
                instruments: [],
                metadataConfidence: 0.0,
                addedDate: Self.parseIADate(doc.addeddate)
            )
            t.recordingDate = Self.parseRecordingDate(doc.date, year: doc.year)
            return t.stamped(with: matchTags.map { Channel.stampToken($0) })
        }
    }

    // Tag-only channels (Classical, Ambient): threshold 0.0 because these channels
    // intentionally include composers not in ComposerMap (Beethoven, Mozart, etc.).
    // License filtering happens entirely in mapDoc via LicenseValidator — do NOT
    // put licenseurl wildcards in the Solr query; leading wildcards (*word*) are
    // disabled in Solr by default and cause the whole query to return an error
    // response with no "response" key, making the JSON decode fail.
    func fetchTracks(tags: [String], excludeTags: [String] = []) async throws -> [Track] {
        let tagClause = tags.map { "subject:\"\($0)\"" }.joined(separator: " OR ")
        let excludeClause = excludeTags.map { " NOT subject:\"\($0)\"" }.joined()
        let baseQuery = "mediatype:audio AND (\(tagClause))\(excludeClause)"
        return try await search(query: baseQuery, confidenceThreshold: 0.0)
    }

    // Spoken-word fetch (LibriVox, podcast collections). Skips MetadataNormalizer —
    // these items are from curated trusted collections, no composer/instrument needed.
    func fetchSpokenWordTracks(channel: Channel) async throws -> [Track] {
        let collections = channel.spokenWordCollections.isEmpty
            ? ["librivoxaudio"] : channel.spokenWordCollections
        let collectionClause = collections.map { "collection:\"\($0)\"" }.joined(separator: " OR ")
        let subjectClause = channel.tags.map { "subject:\"\($0)\"" }.joined(separator: " OR ")
        let query = channel.tags.isEmpty
            ? "mediatype:audio AND (\(collectionClause))"
            : "mediatype:audio AND (\(collectionClause)) AND (\(subjectClause))"
        return try await searchSpokenWord(query: query, tags: channel.tags)
    }

    private func searchSpokenWord(query: String, tags: [String]) async throws -> [Track] {
        var components = URLComponents(string: Self.searchBase)!
        components.queryItems = [
            URLQueryItem(name: "q",       value: query),
            URLQueryItem(name: "fl[]",    value: "identifier"),
            URLQueryItem(name: "fl[]",    value: "title"),
            URLQueryItem(name: "fl[]",    value: "creator"),
            URLQueryItem(name: "fl[]",    value: "subject"),
            URLQueryItem(name: "fl[]",    value: "licenseurl"),
            URLQueryItem(name: "fl[]",    value: "year"),
            URLQueryItem(name: "fl[]",    value: "collection"),
            URLQueryItem(name: "fl[]",    value: "addeddate"),
            URLQueryItem(name: "output",  value: "json"),
            URLQueryItem(name: "rows",    value: "100"),
            URLQueryItem(name: "sort[]",  value: "addeddate desc"),
        ]
        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(IASearchResponse.self, from: data)
        return response.response.docs.compactMap { mapSpokenWordDoc($0, channelTags: tags) }
    }

    private func mapSpokenWordDoc(_ doc: IADoc, channelTags: [String]) -> Track? {
        let license = validator.validate(
            licenseURL: doc.licenseurl,
            year: doc.year,
            collection: doc.collection.first
        )
        guard license != .rejected else { return nil }

        let encoded = doc.identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doc.identifier
        guard let streamURL = URL(string: "https://archive.org/download/\(encoded)") else { return nil }
        // Merge channel tags with IA subject tags so Channel.matches() works correctly.
        let trackTags = Array(Set(channelTags + doc.subjects.map { $0.lowercased() }))

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
            tags: trackTags,
            qualityScore: 0.7,
            rawCreator: doc.creator ?? "",
            composer: nil,
            instruments: [],
            metadataConfidence: 2.0,
            addedDate: Self.parseIADate(doc.addeddate)
        )
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
                let enc = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.name
                if let url = URL(string: "https://archive.org/download/\(encodedId)/\(enc)") { return url }
            }
        }
        // Fallback: accept any audio file by extension for collections using non-standard format labels.
        let audioExtensions: Set<String> = ["mp3", "ogg", "flac", "m4a", "aac", "opus", "wav"]
        if let file = meta.files.first(where: {
            let ext = ($0.name as NSString).pathExtension.lowercased()
            return audioExtensions.contains(ext)
        }) {
            let enc = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.name
            if let url = URL(string: "https://archive.org/download/\(encodedId)/\(enc)") { return url }
        }
        throw URLError(.unsupportedURL)
    }

    // MARK: - Search (used by SearchViewModel)

    // General default-field search (title/creator/description/subject/text),
    // matching the Internet Archive website. A field-scoped form like
    // `title:(a b)` ANDs the words within ONE field and misses most hits
    // (e.g. "Tarrega Guitar" → 2 vs 36).
    func search(query: String, page: Int,
                scope: SearchViewModel.SearchScope = .all) async throws -> [SearchViewModel.ResultGroup] {
        let q = Self.buildSearchQuery(rawInput: query, scope: scope)
        return try await searchGroups(query: q, page: page)
    }

    /// Turn a free-text search like "tarrega guitar" into a Solr query whose
    /// scoring matches archive.org's own web search. Each whitespace-separated
    /// token must match somewhere — in title, creator, or subject — but the
    /// match doesn't have to be in the same field for every token. This is
    /// what archive.org/search?query= does in its frontend, and it's what
    /// makes "tarrega guitar" surface Tárrega guitar recordings instead of
    /// "any recent upload that contains the word tarrega OR guitar".
    ///
    /// Notes:
    /// - We do NOT pass the raw query into Solr's default field — that field
    ///   parser does OR-of-tokens and was the root cause of the pop-music
    ///   pollution the user reported.
    /// - We do NOT apply `sort[]=addeddate desc` (caller drops it) so IA's
    ///   relevance scoring wins.
    /// - Boosts: title:^4 / creator:^3 / subject:^1 so "Tárrega Recuerdos"
    ///   wins over "Top 100 Songs mentioning Tárrega".
    static func buildSearchQuery(rawInput: String,
                                 scope: SearchViewModel.SearchScope = .all) -> String {
        let scopeClause = Self.scopeClause(scope)
        let tokens = rawInput
            .split { !$0.isLetter && !$0.isNumber }
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "mediatype:audio" + scopeClause }
        // Each token must match somewhere (title/creator/subject), AND'd.
        let perToken = tokens.map {
            "(title:\"\($0)\"^4 OR creator:\"\($0)\"^3 OR subject:\"\($0)\"^1)"
        }.joined(separator: " AND ")
        // ANCHOR: at least one token must hit title or creator. This is what
        // keeps keyword-stuffed talk-radio items (e.g. Alan Watt, whose huge
        // subject lists otherwise match any words) out of the results while
        // still letting a token match purely in subject when another token
        // anchors the item (e.g. "tarrega guitar" → Tárrega in the title,
        // guitar in the subject).
        let anchor = tokens.map {
            "title:\"\($0)\" OR creator:\"\($0)\""
        }.joined(separator: " OR ")
        return "mediatype:audio AND \(perToken) AND (\(anchor))" + scopeClause
    }

    // Collection filter for the search scope. Curl-verified against
    // archive.org: audiobooks restricts to the LibriVox / audio-books
    // collections; music EXCLUDES those plus podcast/old-time-radio collections
    // (which otherwise dominate a music search via relevance). NB: no leading
    // wildcards (IA disables them) — these are exact collection ids.
    private static func scopeClause(_ scope: SearchViewModel.SearchScope) -> String {
        switch scope {
        case .all:
            return ""
        case .audiobooks:
            return " AND collection:(librivoxaudio OR audio_bookspoetry)"
        case .music:
            return " AND NOT collection:(librivoxaudio OR audio_bookspoetry"
                 + " OR podcasts OR podcasts_mirror OR podcasts_mirror_bobarchives"
                 + " OR radioprograms OR oldtimeradio)"
        }
    }

    // IA search docs carry no runtime or file count. One metadata GET yields
    // both the total duration (song-vs-book signal) AND the number of audio
    // parts in the single best format — the SAME selection
    // fetchTracksForIdentifier uses, so the search marker matches what
    // "Add Book/Album to Playlist" would actually add.
    func itemInfo(forIdentifier identifier: String) async -> (duration: Double, audioCount: Int)? {
        guard let enc = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://archive.org/metadata/\(enc)"),
              let (data, _) = try? await session.data(from: url) else { return nil }
        struct Meta: Decodable {
            struct F: Decodable { let name: String; let length: String?; let format: String? }
            let files: [F]
        }
        guard let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return nil }
        let selectors: [(Meta.F) -> Bool] = [
            { $0.format == "VBR MP3" }, { $0.format == "128Kbps MP3" },
            { $0.format == "64Kbps MP3" }, { $0.format == "MP3" },
            { $0.format == "Ogg Vorbis" },
            { ($0.name as NSString).pathExtension.lowercased() == "mp3" },
            { ($0.name as NSString).pathExtension.lowercased() == "m4a" },
            { ($0.name as NSString).pathExtension.lowercased() == "aac" },
            { ($0.name as NSString).pathExtension.lowercased() == "opus" },
            { ($0.name as NSString).pathExtension.lowercased() == "ogg" },
            { ($0.name as NSString).pathExtension.lowercased() == "flac" },
            { ($0.name as NSString).pathExtension.lowercased() == "wav" },
        ]
        let chosen = selectors.lazy
            .map { sel in meta.files.filter(sel) }
            .first { !$0.isEmpty } ?? []
        guard !chosen.isEmpty else { return nil }
        let total = chosen.reduce(0.0) { $0 + Self.parseRuntime($1.length) }
        return (duration: total, audioCount: chosen.count)
    }

    func fetchTracksForIdentifier(_ identifier: String) async throws -> [Track] {
        guard let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let metaURL = URL(string: "https://archive.org/metadata/\(encoded)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(from: metaURL)

        struct IAMetaFull: Decodable {
            struct IAMetaFile: Decodable {
                let name: String
                let format: String?
                let length: String?
                let title: String?
                let creator: String?
            }
            struct IAMetaMetadata: Decodable {
                let title: String?
                let creator: String?
                let licenseurl: String?
                let year: Int?
                enum CodingKeys: String, CodingKey { case title, creator, licenseurl, year }
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    title      = try? c.decode(String.self, forKey: .title)
                    creator    = try? c.decode(String.self, forKey: .creator)
                    licenseurl = try? c.decode(String.self, forKey: .licenseurl)
                    if let y = try? c.decode(Int.self, forKey: .year) { year = y }
                    else if let s = try? c.decode(String.self, forKey: .year) { year = Int(s) }
                    else { year = nil }
                }
            }
            let files: [IAMetaFile]
            let metadata: IAMetaMetadata
        }

        let meta = try JSONDecoder().decode(IAMetaFull.self, from: data)

        // Pick exactly ONE audio format. IA items frequently expose the same
        // chapters in MP3 + OGG + FLAC + WAV; mixing them yielded N×formats
        // bogus "parts" with scrambled order. The first selector (in quality
        // priority) that matches ≥1 file wins; only those files are used.
        let selectors: [(IAMetaFull.IAMetaFile) -> Bool] = [
            { $0.format == "VBR MP3" },
            { $0.format == "128Kbps MP3" },
            { $0.format == "64Kbps MP3" },
            { $0.format == "MP3" },
            { $0.format == "Ogg Vorbis" },
            { ($0.name as NSString).pathExtension.lowercased() == "mp3" },
            { ($0.name as NSString).pathExtension.lowercased() == "m4a" },
            { ($0.name as NSString).pathExtension.lowercased() == "aac" },
            { ($0.name as NSString).pathExtension.lowercased() == "opus" },
            { ($0.name as NSString).pathExtension.lowercased() == "ogg" },
            { ($0.name as NSString).pathExtension.lowercased() == "flac" },
            { ($0.name as NSString).pathExtension.lowercased() == "wav" },
        ]
        let chosen = selectors.lazy
            .map { sel in meta.files.filter(sel) }
            .first { !$0.isEmpty } ?? []

        // Finder-style natural order so laws_01 < laws_02 < … < laws_10 < … <
        // laws_20 (and chapter 2 < chapter 10) — guarantees book/album order.
        let audioFiles = chosen.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        let itemTitle = meta.metadata.title ?? identifier
        let itemCreator = meta.metadata.creator ?? "Unknown"
        let licenseURL = meta.metadata.licenseurl
        let license = validator.validate(licenseURL: licenseURL, year: meta.metadata.year, collection: nil)
        let isMulti = audioFiles.count > 1

        return audioFiles.enumerated().compactMap { index, file in
            let enc = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.name
            guard let streamURL = URL(string: "https://archive.org/download/\(encoded)/\(enc)") else { return nil }
            return Track(
                id: "\(identifier)/\(file.name)",
                source: "internet_archive",
                title: file.title ?? (isMulti ? file.name : itemTitle),
                artist: file.creator ?? itemCreator,
                duration: Self.parseRuntime(file.length),
                streamURL: streamURL,
                downloadURL: streamURL,
                localFilePath: nil,
                license: license,
                tags: [],
                qualityScore: 0.7,
                rawCreator: file.creator ?? itemCreator,
                composer: nil,
                instruments: [],
                metadataConfidence: 1.0,
                addedDate: nil,
                partNumber: isMulti ? index + 1 : nil,
                totalParts: isMulti ? audioFiles.count : nil,
                parentIdentifier: isMulti ? identifier : nil,
                isMultiPart: isMulti ? true : false
            )
        }
    }

    private func searchGroups(
        query: String,
        page: Int
    ) async throws -> [SearchViewModel.ResultGroup] {
        var components = URLComponents(string: Self.searchBase)!
        components.queryItems = [
            URLQueryItem(name: "q",       value: query),
            URLQueryItem(name: "fl[]",    value: "identifier"),
            URLQueryItem(name: "fl[]",    value: "title"),
            URLQueryItem(name: "fl[]",    value: "creator"),
            URLQueryItem(name: "fl[]",    value: "addeddate"),
            URLQueryItem(name: "fl[]",    value: "runtime"),
            URLQueryItem(name: "fl[]",    value: "collection"),
            URLQueryItem(name: "output",  value: "json"),
            URLQueryItem(name: "rows",    value: "20"),
            URLQueryItem(name: "start",   value: "\(page * 20)"),
            URLQueryItem(name: "sort[]",  value: "downloads desc"),
        ]
        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(IASearchResponse.self, from: data)
        return response.response.docs.map { doc in
            SearchViewModel.ResultGroup(
                id: doc.identifier,
                title: doc.title ?? doc.identifier,
                creator: doc.creator ?? "Unknown",
                addedDate: Self.parseIADate(doc.addeddate),
                duration: Self.parseRuntime(doc.runtime),
                collection: doc.collection.first
            )
        }
    }

    // IA `runtime` is usually "H:MM:SS"/"MM:SS"; sometimes plain seconds.
    private static func parseRuntime(_ raw: String?) -> Double {
        guard let s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return 0 }
        if let d = Double(s) { return d }
        let parts = s.split(separator: ":").compactMap { Double($0) }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return 0
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
        let broadcastFilter = " NOT creator:PBS NOT creator:BBC NOT creator:CBC NOT creator:NPR"
        return "mediatype:audio AND (\(creatorClause))\(broadcastFilter)"
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
            URLQueryItem(name: "fl[]",    value: "addeddate"),
            URLQueryItem(name: "output",  value: "json"),
            URLQueryItem(name: "rows",    value: "100"),
            URLQueryItem(name: "sort[]",  value: "addeddate desc"),
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

        let encodedId = doc.identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doc.identifier
        guard let streamURL = URL(string: "https://archive.org/download/\(encodedId)") else { return nil }

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
            tags: doc.subjects.map { $0.lowercased() },
            qualityScore: min(confidence / 4.0, 1.0),
            rawCreator: doc.creator ?? "",
            composer: composer,
            instruments: instruments,
            metadataConfidence: confidence,
            addedDate: Self.parseIADate(doc.addeddate)
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
    let addeddate: String?
    let date: String?
    let runtime: String?
    let downloads: Int?   // IA all-time download count — used as a quality signal

    enum CodingKeys: String, CodingKey {
        case identifier, title, creator, licenseurl, description, year, addeddate
        case subject, collection, date, runtime, downloads
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

        addeddate = try? c.decode(String.self, forKey: .addeddate)

        // date: String or [String] (IA original publication/recording date)
        if let arr = try? c.decode([String].self, forKey: .date) {
            date = arr.first
        } else {
            date = try? c.decode(String.self, forKey: .date)
        }

        // runtime: String or [String] (item duration, "H:MM:SS")
        if let arr = try? c.decode([String].self, forKey: .runtime) {
            runtime = arr.first
        } else {
            runtime = try? c.decode(String.self, forKey: .runtime)
        }

        // downloads: Int or String (IA sometimes serialises numerics as strings)
        if let n = try? c.decode(Int.self, forKey: .downloads) {
            downloads = n
        } else if let s = try? c.decode(String.self, forKey: .downloads), let n = Int(s) {
            downloads = n
        } else {
            downloads = nil
        }
    }
}

/// Maps an Internet Archive all-time download count to a 0.1…1.0 quality weight.
/// Log-scaled so a viral item isn't 1000× an obscure one (just a few ×), and
/// floored at 0.1 so a low-download item is DOWN-weighted, never excluded — the
/// curated query stays the curation; this only biases which of its results
/// surface more often (QueueManager.selectionWeight multiplies by this). See
/// ASSESSMENT.md #3 (curate down).
enum IAQualityScore {
    static func fromDownloads(_ downloads: Int?) -> Double {
        guard let d = downloads, d > 0 else { return 0.1 }
        let normalized = min(log10(Double(d) + 1) / 5.0, 1.0)   // ~100k downloads → 1.0
        return normalized * 0.9 + 0.1                            // → [0.1, 1.0]
    }
}
