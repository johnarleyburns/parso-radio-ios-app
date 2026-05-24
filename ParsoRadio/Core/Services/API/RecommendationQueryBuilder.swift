import Foundation

/// Builds Internet Archive queries for the "for you" channels from a user's
/// listening history. Pure & deterministic (given the same history → same
/// queries) so it is fully unit-testable. Each arm returns nil when there isn't
/// enough of its signal yet — the caller shows the "listen to N tracks" prompt
/// only when BOTH arms are nil.
///
/// Two-arm design (see RECOMMENDATIONS-DESIGN.md). The channel fetches with
/// `sort=random`, which discards Solr relevance — so the old single query's
/// `creator:^3` boosts did NOTHING, and a broad `subject:"Classical"` match was
/// as likely as a real performer the user played (amateur uploads, mis-tagged
/// vaporwave, sermons leaked in). Instead we fetch two SEPARATE arms and bias
/// the POOL COMPOSITION toward signal:
///   • Creator arm — only artists the user actually played ("more of them").
///   • Subject arm — their top genres ("discover new artists, in your taste").
/// `mixPool` then builds a pool that is ~`creatorShare` creator-origin; the
/// channel's existing random selection turns that composition into play time.
enum RecommendationQueryBuilder {
    /// Minimum distinct qualifying plays before a recommendation channel turns on.
    static let minPlays = 5
    /// How many top creators / subjects to fold into each arm.
    static let maxCreators = 12
    static let maxSubjects = 6
    /// Download floor for the MUSIC arms. Trims the amateur long tail; curl shows
    /// ~23%→~15% noise at 100 with a still-large pool. Do NOT raise much further —
    /// viral novelty ("Baby Mozart") has huge download counts, so an over-high
    /// floor brings noise BACK (curl: noise climbs again at 1000). Books arms use
    /// no floor — they're already scoped to curated audiobook collections.
    static let downloadsFloor = 100
    /// Target pool size and the share of it drawn from the creator (signal) arm.
    static let poolSize = 120
    static let creatorShare = 0.7

    /// Top values by frequency, most-played first, capped. Ties keep first-seen
    /// (most-recent, since history is newest-first) for determinism.
    static func topValues(_ values: [String], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for raw in values {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { continue }
            if counts[v] == nil { order.append(v) }
            counts[v, default: 0] += 1
        }
        return order
            .sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    private static func creators(from tracks: [Track]) -> [String] {
        // Skip the "Unknown"/empty artist placeholder so it never anchors a query.
        topValues(tracks.map(\.artist).filter {
            let a = $0.trimmingCharacters(in: .whitespaces).lowercased()
            return !a.isEmpty && a != "unknown"
        }, limit: maxCreators)
    }

    private static func subjects(from tracks: [Track]) -> [String] {
        topValues(tracks.flatMap { $0.tags }, limit: maxSubjects)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: " ")
    }

    private static func orClause(_ field: String, _ values: [String]) -> String {
        values.map { "\(field):\"\(escape($0))\"" }.joined(separator: " OR ")
    }

    // Music: exclude the other medium (spoken word / audiobook collections) and
    // apply the download floor.
    private static let musicExclusions =
        " AND NOT (subject:audiobook OR subject:audiobooks OR subject:interview"
      + " OR subject:lecture OR subject:speech OR subject:sermon"
      + " OR collection:librivoxaudio OR collection:audio_bookspoetry"
      + " OR collection:podcasts OR collection:radio)"
    private static var musicDownloadsGate: String { " AND downloads:[\(downloadsFloor) TO *]" }

    // Books: scope to the audiobook collections; only drop the non-book media.
    private static let booksScope = " AND (collection:librivoxaudio OR collection:audio_bookspoetry)"
    private static let booksExclusions = " AND NOT (subject:interview OR subject:lecture OR subject:sermon)"

    // MARK: - Music arms

    /// "Music for You" — signal arm: more of the artists they played. nil if no
    /// real creators yet (or below minPlays).
    static func musicCreatorQuery(fromHistory tracks: [Track]) -> String? {
        guard tracks.count >= minPlays else { return nil }
        let cre = creators(from: tracks)
        guard !cre.isEmpty else { return nil }
        return "mediatype:audio AND (\(orClause("creator", cre)))" + musicExclusions + musicDownloadsGate
    }

    /// "Music for You" — discovery arm: more in their genres (new artists). nil if
    /// no subjects yet (or below minPlays).
    static func musicSubjectQuery(fromHistory tracks: [Track]) -> String? {
        guard tracks.count >= minPlays else { return nil }
        let subj = subjects(from: tracks)
        guard !subj.isEmpty else { return nil }
        return "mediatype:audio AND (\(orClause("subject", subj)))" + musicExclusions + musicDownloadsGate
    }

    // MARK: - Books arms

    static func booksCreatorQuery(fromHistory tracks: [Track]) -> String? {
        guard tracks.count >= minPlays else { return nil }
        let cre = creators(from: tracks)
        guard !cre.isEmpty else { return nil }
        return "mediatype:audio" + booksScope + " AND (\(orClause("creator", cre)))" + booksExclusions
    }

    static func booksSubjectQuery(fromHistory tracks: [Track]) -> String? {
        guard tracks.count >= minPlays else { return nil }
        let subj = subjects(from: tracks)
        guard !subj.isEmpty else { return nil }
        return "mediatype:audio" + booksScope + " AND (\(orClause("subject", subj)))" + booksExclusions
    }

    // MARK: - Pool mix

    /// Build a deduped pool of up to `total`, biased to `creatorShare` from the
    /// creator (signal) arm with the remainder from the subject (discovery) arm.
    /// If the subject arm is thin, top up from leftover creator tracks (and vice
    /// versa) so a short arm never shrinks the pool. Pure & order-deterministic.
    static func mixPool(creatorTracks: [Track], subjectTracks: [Track],
                        total: Int = poolSize, creatorShare: Double = creatorShare) -> [Track] {
        var seen = Set<String>()
        var result: [Track] = []
        func take(_ tracks: [Track], upTo cap: Int) {
            for t in tracks {
                if result.count >= cap { break }
                if seen.insert(t.id).inserted { result.append(t) }
            }
        }
        let creatorTarget = min(total, Int((Double(total) * creatorShare).rounded()))
        take(creatorTracks, upTo: creatorTarget)   // signal first, up to its share
        take(subjectTracks, upTo: total)           // fill remainder with discovery
        take(creatorTracks, upTo: total)           // subject arm thin → more signal
        return result
    }
}
