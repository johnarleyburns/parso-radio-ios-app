import Foundation

/// Builds Internet Archive queries for the "for you" channels from a user's
/// listening history. Pure & deterministic (given the same history → same
/// query) so it is fully unit-testable. Returns nil when there isn't enough
/// history yet — the caller shows the "listen to N tracks first" prompt.
///
/// Philosophy mirrors the curated channels: lean on the strong signal (the
/// CREATORS the user actually played, boosted) plus a few of their top subjects,
/// and exclude the other medium (no spoken word in Music, music-only sources in
/// Books). It's "more of what you've been playing," not true discovery.
enum RecommendationQueryBuilder {
    /// Minimum distinct qualifying plays before a recommendation channel turns on.
    static let minPlays = 5
    /// How many top creators / subjects to fold into the query.
    static let maxCreators = 12
    static let maxSubjects = 6

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

    /// "Music for You": more of the artists/genres they play, with spoken-word
    /// and audiobook sources excluded. nil if < minPlays distinct music plays.
    static func musicQuery(fromHistory tracks: [Track]) -> String? {
        guard tracks.count >= minPlays else { return nil }
        let cre = creators(from: tracks)
        let subj = subjects(from: tracks)
        guard !cre.isEmpty else { return nil }
        var arms = cre.map { "creator:\"\(escape($0))\"^3" }
        arms += subj.map { "subject:\"\(escape($0))\"" }
        let positive = arms.joined(separator: " OR ")
        return "mediatype:audio AND (\(positive))"
            + " AND NOT (subject:audiobook OR subject:audiobooks OR subject:interview"
            + " OR subject:lecture OR subject:speech OR subject:sermon"
            + " OR collection:librivoxaudio OR collection:audio_bookspoetry"
            + " OR collection:podcasts OR collection:radio)"
            + " AND downloads:[20 TO *]"
    }

    /// "Books for You": more audiobooks by the authors/genres they listen to,
    /// limited to the audiobook collections. nil if < minPlays distinct plays.
    static func booksQuery(fromHistory tracks: [Track]) -> String? {
        guard tracks.count >= minPlays else { return nil }
        let cre = creators(from: tracks)
        let subj = subjects(from: tracks)
        guard !cre.isEmpty else { return nil }
        var arms = cre.map { "creator:\"\(escape($0))\"^3" }
        arms += subj.map { "subject:\"\(escape($0))\"" }
        let positive = arms.joined(separator: " OR ")
        return "mediatype:audio"
            + " AND (collection:librivoxaudio OR collection:audio_bookspoetry)"
            + " AND (\(positive))"
            + " AND NOT (subject:interview OR subject:lecture OR subject:sermon)"
    }
}
