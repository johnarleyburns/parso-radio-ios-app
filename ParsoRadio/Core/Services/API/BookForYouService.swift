import Foundation

struct BookCandidate: Equatable, Sendable {
    let identifier: String
    let title: String
    let creator: String
    let subjects: [String]
    let downloads: Int

    var workKey: String {
        BookForYouService.workKey(author: creator, title: title)
    }
}

struct BookForYouService {
    private let db: DatabaseService
    private let tasteStore: TasteProfileStore?
    private let session: URLSession

    static let searchBase = "https://archive.org/advancedsearch.php"
    static let librivoxCollection = "collection:librivoxaudio"

    init(db: DatabaseService, tasteStore: TasteProfileStore? = nil,
         session: URLSession = .app) {
        self.db = db
        self.tasteStore = tasteStore
        self.session = session
    }

    // MARK: - Work-Key Normalization (§5.0)

    static func workKey(author: String, title: String) -> String {
        let normalizedAuthor = author.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        let cleaned = cleanTitle(title)
        return "\(normalizedAuthor)·\(cleaned)"
    }

    static func cleanTitle(_ raw: String) -> String {
        var t = raw
        // Strip common LibriVox parenthetical suffixes
        let patterns: [String] = [
            #"\(version\s*\d+\)"#,         // (version 2), (version 3)
            #"\(dramatic reading\)"#,      // (dramatic reading)
            #"\(read by [^)]+\)"#,          // (read by Stewart Wills)
            #"\(solo\)"#,                    // (solo)
            #"\(group\)"#,                  // (group)
            #"\(in [^)]+\)"#,               // (in Russian), (in French)
            #"\(unabridged\)"#,             // (unabridged)
            #"\(abridged\)"#,               // (abridged)
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern,
                                                     options: [.caseInsensitive]) {
                t = regex.stringByReplacingMatches(in: t,
                    range: NSRange(location: 0, length: t.utf16.count),
                    withTemplate: "")
            }
        }
        t = t.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return t
    }

    // MARK: - Date-Seeded RNG (§5.6)

    static func choose<T>(from pool: [T], seed: String) -> T? {
        guard !pool.isEmpty else { return nil }
        let idx = abs(seed.hashValue) % pool.count
        return pool[idx]
    }

    // MARK: - Main Entry Point (§5.5)

    func generatePick(for day: String) async -> BookForYouEntry? {
        let exclusionKeys = await allExclusionKeys()

        // 1. Personalized pool
        if let profile = await tasteStore?.fetchProfile(bucket: "spoken") {
            if !profile.isEmpty {
                if let candidates = await personalizedCandidates(profile: profile),
                   let filtered = await filterAndPick(from: candidates,
                                                      excluding: exclusionKeys,
                                                      seed: day) {
                    // Reason: match on creator overlap
                    let reason = reasonForPersonalizedPick(filtered, profile: profile)
                    let entry = BookForYouEntry(
                        identifier: filtered.identifier,
                        title: filtered.title,
                        author: filtered.creator,
                        subjects: filtered.subjects,
                        reason: reason,
                        workKey: filtered.workKey
                    )
                    await persist(entry, day: day)
                    return entry
                }
            }
        }

        // 2. Top-100 General Fiction (§5.3)
        if let candidates = await coldStartCandidates(),
           let filtered = await filterAndPick(from: candidates,
                                              excluding: exclusionKeys,
                                              seed: day) {
            let entry = BookForYouEntry(
                identifier: filtered.identifier,
                title: filtered.title,
                author: filtered.creator,
                subjects: filtered.subjects,
                reason: "Popular on LibriVox",
                workKey: filtered.workKey
            )
            await persist(entry, day: day)
            return entry
        }

        // 3. Broader LibriVox fiction
        if let candidates = await broadLibrivoxCandidates(),
           let filtered = await filterAndPick(from: candidates,
                                              excluding: exclusionKeys,
                                              seed: day) {
            let entry = BookForYouEntry(
                identifier: filtered.identifier,
                title: filtered.title,
                author: filtered.creator,
                subjects: filtered.subjects,
                reason: "Popular on LibriVox",
                workKey: filtered.workKey
            )
            await persist(entry, day: day)
            return entry
        }

        // 4. Any LibriVox by downloads
        if let candidates = await anyLibrivoxCandidates(),
           let filtered = await filterAndPick(from: candidates,
                                              excluding: exclusionKeys,
                                              seed: day) {
            let entry = BookForYouEntry(
                identifier: filtered.identifier,
                title: filtered.title,
                author: filtered.creator,
                subjects: filtered.subjects,
                reason: "Popular on LibriVox",
                workKey: filtered.workKey
            )
            await persist(entry, day: day)
            return entry
        }

        // 5. Least-recently-curated fallback (§5.5 — never nil)
        if let fallback = await db.fetchLeastRecentlyCurated() {
            return fallback
        }

        return nil
    }

    // MARK: - Candidate Pools

    /// Personalized pool from spoken taste profile (§5.2)
    private func personalizedCandidates(profile: ProfileBucket) async -> [BookCandidate]? {
        var all: [BookCandidate] = []

        // EXPLOIT: other books by authors the user has heard
        for creator in profile.topCreators.prefix(5) {
            let escaped = escapeSolr(creator)
            let query = "\(Self.librivoxCollection) AND creator:\"\(escaped)\""
            if let results = try? await searchLibrivox(query: query, rows: 40) {
                all.append(contentsOf: results)
            }
        }

        // EXPLORE: books in genres the user likes
        for subject in profile.topSubjects.prefix(4) {
            let escaped = escapeSolr(subject)
            let query = "\(Self.librivoxCollection) AND subject:\"\(escaped)\""
            if let results = try? await searchLibrivox(query: query, rows: 40) {
                all.append(contentsOf: results)
            }
        }

        // Deduplicate by workKey
        var seen: Set<String> = []
        all = all.filter { seen.insert($0.workKey).inserted }

        return all.isEmpty ? nil : all
    }

    /// Cold start: top 100 General Fiction by downloads (§5.3)
    private func coldStartCandidates() async -> [BookCandidate]? {
        let query = "\(Self.librivoxCollection) AND subject:\"General Fiction\""
        return try? await searchLibrivox(query: query, rows: 100)
    }

    /// Broader LibriVox fiction
    private func broadLibrivoxCandidates() async -> [BookCandidate]? {
        let orSet = [
            "librivoxaudio",
            "audio_bookspoetry"
        ].map { "collection:\"\($0)\"" }.joined(separator: " OR ")
        let query = "mediatype:audio AND (\(orSet))"
        return try? await searchLibrivox(query: query, rows: 300)
    }

    /// Any LibriVox item by downloads
    private func anyLibrivoxCandidates() async -> [BookCandidate]? {
        let query = Self.librivoxCollection
        return try? await searchLibrivox(query: query, rows: 500)
    }

    // MARK: - Exclusion + Pick

    private func allExclusionKeys() async -> Set<String> {
        let listened = await db.fetchBookListenedWorkKeys()
        let curated = await db.fetchBookCuratedWorkKeys()
        return listened.union(curated)
    }

    private func filterAndPick(from candidates: [BookCandidate],
                               excluding exclusionKeys: Set<String>,
                               seed: String) async -> BookCandidate? {
        let filtered = candidates.filter { !exclusionKeys.contains($0.workKey) }
        return Self.choose(from: filtered, seed: seed)
    }

    // MARK: - Persist

    private func persist(_ entry: BookForYouEntry, day: String) async {
        await db.insertBookCurated(entry, day: day)
    }

    // MARK: - Reason

    private func reasonForPersonalizedPick(_ candidate: BookCandidate,
                                           profile: ProfileBucket) -> String {
        let authorLower = candidate.creator.lowercased()
        for creator in profile.topCreators {
            if creator.lowercased() == authorLower {
                return "Because you enjoyed \(creator)"
            }
        }
        if let firstSubject = profile.topSubjects.first {
            return "More \(firstSubject), like your history"
        }
        return "Popular on LibriVox"
    }

    // MARK: - IA LibriVox Query

    private func searchLibrivox(query: String,
                                rows: Int) async throws -> [BookCandidate] {
        var components = URLComponents(string: Self.searchBase)!
        components.queryItems = [
            URLQueryItem(name: "q",       value: query),
            URLQueryItem(name: "fl[]",    value: "identifier"),
            URLQueryItem(name: "fl[]",    value: "title"),
            URLQueryItem(name: "fl[]",    value: "creator"),
            URLQueryItem(name: "fl[]",    value: "subject"),
            URLQueryItem(name: "fl[]",    value: "downloads"),
            URLQueryItem(name: "output",  value: "json"),
            URLQueryItem(name: "rows",    value: "\(rows)"),
            URLQueryItem(name: "sort[]",  value: "downloads desc"),
        ]
        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(IASearchResponse.self, from: data)
        return response.response.docs.map { doc in
            BookCandidate(
                identifier: doc.identifier,
                title: doc.title ?? doc.identifier,
                creator: doc.creator ?? "Unknown",
                subjects: doc.subjects,
                downloads: doc.downloads ?? 0
            )
        }
    }

    // MARK: - Solr Escaping

    private func escapeSolr(_ term: String) -> String {
        let specials: Set<Character> = ["+", "-", "!", "(", ")", "{", "}",
                                         "[", "]", "^", "\"", "~", "*", "?",
                                         ":", "\\", "/"]
        var escaped = ""
        for ch in term {
            if specials.contains(ch) { escaped.append("\\") }
            escaped.append(ch)
        }
        return escaped
    }
}


