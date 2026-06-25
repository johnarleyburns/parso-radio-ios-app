import Foundation

struct TasteTerm: Equatable {
    let axis: String
    let term: String
    let weight: Double
}

struct ProfileBucket: Equatable {
    let bucket: String
    let creatorTerms: [TasteTerm]
    let subjectTerms: [TasteTerm]
    let composerTerms: [TasteTerm]

    var topCreators: [String] { creatorTerms.prefix(5).map(\.term) }
    var topSubjects: [String] { subjectTerms.prefix(8).map(\.term) }
    var topComposers: [String] { composerTerms.prefix(3).map(\.term) }

    var isEmpty: Bool { creatorTerms.isEmpty && subjectTerms.isEmpty && composerTerms.isEmpty }

    func allTerms() -> [TasteTerm] { creatorTerms + subjectTerms + composerTerms }
}

@MainActor
final class TasteProfileStore {
    private let db: DatabaseService

    init(db: DatabaseService) {
        self.db = db
    }

    func hasProfile(bucket: String? = nil) async -> Bool {
        let terms = await db.fetchTasteProfileTerms(bucket: bucket)
        return !terms.isEmpty
    }

    func hasAnyProfile() async -> Bool {
        let terms = await db.fetchTasteProfileTerms(bucket: nil)
        return !terms.isEmpty
    }

    // MARK: - Upsert terms (decay update)

    func upsertTerm(bucket: String, axis: String, term: String, increment: Double) async {
        let now = Date().timeIntervalSince1970
        await db.upsertTasteProfileTerm(bucket: bucket, axis: axis, term: term,
                                         increment: increment, now: now,
                                         tau: RecommendationConstants.tau)
    }

    func seedFromTrack(_ track: Track, channel: Channel?, boost: Double = 1.0) async {
        let kind = resolvedKind(track: track, channel: channel)
        await seedFromTrack(track, mediaKind: kind, boost: boost, channel: channel)
    }

    /// Seed with an explicit, already-resolved media kind. Live playback passes
    /// `PlayerViewModel.activeMediaKind` here so audiobook plays (including
    /// whole-book album plays that carry no channel) reliably land in the
    /// `spoken` bucket and music plays land in `music`.
    func seedFromTrack(_ track: Track, mediaKind: MediaKind, boost: Double = 1.0,
                       channel: Channel? = nil) async {
        guard let b = bucketFor(mediaKind) else { return }
        let increment = 1.0 * boost

        let creator = track.rawCreator.trimmingCharacters(in: .whitespaces)
        if !creator.isEmpty, creator != "Unknown", creator != "Various" {
            await upsertTerm(bucket: b, axis: "creator", term: creator.lowercased(), increment: increment)
        }
        if let composer = track.composer?.trimmingCharacters(in: .whitespaces),
           !composer.isEmpty {
            await upsertTerm(bucket: b, axis: "composer", term: composer.lowercased(), increment: increment)
        }
        for tag in track.tags {
            let t = tag.lowercased().trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !RecommendationConstants.subjectStopList.contains(t) {
                await upsertTerm(bucket: b, axis: "subject", term: t, increment: increment)
            }
        }
        if let c = channel {
            await seedSubjectFromChannel(c, bucket: b, increment: increment)
        }
    }

    func seedFavoriteBoostFromTrack(_ track: Track, channel: Channel?) async {
        await seedFromTrack(track, channel: channel, boost: RecommendationConstants.favoriteBoost)
    }

    /// Favorite boost using an explicit, already-resolved media kind — used by
    /// the player surfaces where the play has no channel (album/book plays).
    func seedFavoriteBoostFromTrack(_ track: Track, mediaKind: MediaKind) async {
        await seedFromTrack(track, mediaKind: mediaKind, boost: RecommendationConstants.favoriteBoost)
    }

    private func seedSubjectFromChannel(_ channel: Channel, bucket: String, increment: Double) async {
        for tag in channel.tags {
            let t = tag.lowercased().trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !RecommendationConstants.subjectStopList.contains(t) {
                await upsertTerm(bucket: bucket, axis: "subject", term: t, increment: increment)
            }
        }
    }

    // MARK: - Profile read (with subject damp)

    func fetchProfile(bucket: String) async -> ProfileBucket {
        let rawTerms = await db.fetchTasteProfileTerms(bucket: bucket)
        var creators: [TasteTerm] = []
        var subjects: [TasteTerm] = []
        var composers: [TasteTerm] = []

        let subjectWeights = rawTerms.filter { $0.axis == "subject" }
        let distinctSubjectCount = Set(subjectWeights.map(\.term)).count
        let subjectDampDivisor = distinctSubjectCount > 0
            ? 1.0 + log(Double(distinctSubjectCount) + 1.0)
            : 1.0

        for t in rawTerms {
            var weight = t.weight
            if t.axis == "subject" {
                if RecommendationConstants.subjectStopList.contains(t.term) {
                    weight *= 0.05
                } else {
                    weight /= subjectDampDivisor
                }
            }
            let term = TasteTerm(axis: t.axis, term: t.term, weight: weight)
            switch t.axis {
            case "creator": creators.append(term)
            case "subject": subjects.append(term)
            case "composer": composers.append(term)
            default: break
            }
        }

        creators.sort { $0.weight > $1.weight }
        subjects.sort { $0.weight > $1.weight }
        composers.sort { $0.weight > $1.weight }

        return ProfileBucket(bucket: bucket, creatorTerms: creators,
                             subjectTerms: subjects, composerTerms: composers)
    }

    // MARK: - Seen identifiers

    func addSeenIdentifier(_ identifier: String, reason: String) async {
        await db.upsertTasteSeenIdentifier(identifier, reason: reason)
    }

    func addSeenIdentifiers(from track: Track, reason: String) async {
        if !track.id.isEmpty {
            await addSeenIdentifier(track.id, reason: reason)
        }
        let workKey = workKeyFor(track)
        if workKey != track.id {
            await addSeenIdentifier(workKey, reason: reason)
        }
        if let parent = track.parentIdentifier, !parent.isEmpty, parent != workKey {
            await addSeenIdentifier(parent, reason: reason)
        }
    }

    func fetchSeenIdentifiers() async -> Set<String> {
        await db.fetchTasteSeenIdentifiers()
    }

    // MARK: - Surfaced ring

    func pushSurfaced(_ identifiers: [String]) async {
        await db.pushRecoSurfaced(identifiers, cap: RecommendationConstants.recoSurfacedCap)
    }

    func fetchSurfacedIdentifiers() async -> Set<String> {
        await db.fetchRecoSurfacedIdentifiers()
    }

    // MARK: - Helpers

    func bucketFor(_ kind: MediaKind) -> String? {
        switch kind {
        case .music, .ambient: return "music"
        case .audiobook, .lecture: return "spoken"
        case .podcast: return nil
        }
    }

    /// A non-music channel (Audiobooks / Lectures / Podcasts / Ambient) is
    /// authoritative about content kind. A music channel, the generic `for-you`
    /// channel, and the `direct`/playlist/search contexts (channel `nil`) all
    /// default to `.music`, so we defer to the track's own persisted signals via
    /// `inferredMediaKind` — keeping a LibriVox track classified `.audiobook`
    /// even when it was played without a spoken channel.
    func resolvedKind(track: Track, channel: Channel?) -> MediaKind {
        if let channel, channel.mediaKind != .music {
            return channel.mediaKind
        }
        return track.inferredMediaKind
    }

    func workKeyFor(_ track: Track) -> String {
        if let parent = track.parentIdentifier, !parent.isEmpty { return parent }
        let normalizedCreator = track.rawCreator.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
        let normalizedTitle = track.title.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
        return "\(normalizedCreator)·\(normalizedTitle)"
    }
}
