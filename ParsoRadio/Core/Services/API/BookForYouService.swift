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

        // 1. Personalized pool via Solr (EXPLOIT + EXPLORE on spoken profile).
        //    If Solr is reachable, this gives on-taste picks. If not, skip.
        if let profile = await tasteStore?.fetchProfile(bucket: "spoken"),
           !profile.isEmpty,
           let candidates = await personalizedCandidates(profile: profile),
           let filtered = await filterAndPick(from: candidates,
                                               excluding: exclusionKeys,
                                               seed: day) {
            let reason = reasonForPersonalizedPick(filtered, profile: profile)
            let entry = BookForYouEntry(
                identifier: filtered.identifier, title: filtered.title,
                author: filtered.creator, subjects: filtered.subjects,
                reason: reason, workKey: filtered.workKey
            )
            await persist(entry, day: day)
            return entry
        }

        // 2. Bundled popular LibriVox books (offline, always available).
        //    Equivalent to top-100 General Fiction but doesn't need Solr.
        let bundledCandidates = LibrivoxBundledBooks.candidates
        if !bundledCandidates.isEmpty,
           let filtered = await filterAndPick(from: bundledCandidates,
                                               excluding: exclusionKeys,
                                               seed: day) {
            // Try Solr enrichment in background to add subjects for future days
            let entry = BookForYouEntry(
                identifier: filtered.identifier, title: filtered.title,
                author: filtered.creator, subjects: filtered.subjects,
                reason: "Popular on LibriVox", workKey: filtered.workKey
            )
            await persist(entry, day: day)
            return entry
        }

        // 3. Least-recently-curated fallback (never nil once the ledger has data).
        if let fallback = await db.fetchLeastRecentlyCurated() {
            return fallback
        }

        // 4. Absolute last resort for empty bundle + empty DB.
        let fallbackEntry = BookForYouEntry(
            identifier: "prideandprejudice_2410_librivox",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            subjects: ["fiction", "romance", "classic"],
            reason: "Popular on LibriVox",
            workKey: "jane austen·pride and prejudice"
        )
        await persist(fallbackEntry, day: day)
        return fallbackEntry
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


