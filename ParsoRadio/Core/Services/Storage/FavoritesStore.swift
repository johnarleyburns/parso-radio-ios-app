import Foundation

@MainActor
final class FavoritesStore: ObservableObject {
    @Published var favorites: [Favorite] = []

    let db: DatabaseService
    let tasteStore: TasteProfileStore

    init(db: DatabaseService, tasteStore: TasteProfileStore? = nil) {
        self.db = db
        self.tasteStore = tasteStore ?? TasteProfileStore(db: db)
    }

    func loadAll() async {
        favorites = await db.fetchAllFavorites()
    }

    func isFavorited(id: String) async -> Bool {
        await db.isFavorited(id: id)
    }

    func isFavorited(track: Track, channel: Channel?, mediaKind: MediaKind? = nil) async -> Bool {
        let kind = mediaKind.map(FavoriteKind.init(mediaKind:)) ?? track.favoriteKind(channel: channel)
        let fid = track.favoriteID(for: kind)
        return await db.isFavorited(id: fid)
    }

    func toggle(track: Track, channel: Channel?, mediaKind: MediaKind? = nil,
                positionSeconds: Double? = nil, chapterIndex: Int? = nil) async {
        let kind = mediaKind.map(FavoriteKind.init(mediaKind:)) ?? track.favoriteKind(channel: channel)
        let fid = track.favoriteID(for: kind)

        if await db.isFavorited(id: fid) {
            await db.deleteFavorite(id: fid)
        } else {
            var resumePoint: ResumePoint?
            if kind == .book || kind == .episode || kind == .lecture {
                if let pos = positionSeconds {
                    resumePoint = ResumePoint(
                        chapterIndex: chapterIndex ?? track.partNumber,
                        positionSeconds: pos,
                        updatedAt: Date()
                    )
                }
            }
            let fav = Favorite(
                id: fid,
                kind: kind,
                dateAdded: Date(),
                title: kind == .book
                    ? (track.parentIdentifier ?? track.title)
                    : track.title,
                creator: cleanedArtist(track.artist),
                artworkURL: track.resolvedArtworkURL,
                sourceIdentifier: track.parentIdentifier ?? track.id,
                resumePoint: resumePoint
            )
            await db.saveFavorite(fav)
            if let mk = mediaKind {
                await tasteStore.seedFavoriteBoostFromTrack(track, mediaKind: mk)
            } else {
                await tasteStore.seedFavoriteBoostFromTrack(track, channel: channel)
            }
            await tasteStore.addSeenIdentifiers(from: track, reason: "favorited")
        }
        await loadAll()
    }

    func updateResumePoint(forFavoriteId fid: String, positionSeconds: Double,
                           chapterIndex: Int?) async {
        let rp = ResumePoint(
            chapterIndex: chapterIndex,
            positionSeconds: positionSeconds,
            updatedAt: Date()
        )
        await db.updateResumePoint(favoriteId: fid, resumePoint: rp)
        await loadAll()
    }

    func songs() -> [Favorite] {
        favorites.filter { $0.kind == .track }
    }

    func books() -> [Favorite] {
        favorites.filter { $0.kind == .book }
    }

    func episodes() -> [Favorite] {
        favorites.filter { $0.kind == .episode }
    }

    func lectures() -> [Favorite] {
        favorites.filter { $0.kind == .lecture }
    }

    func hasAnyFavorites() -> Bool {
        !favorites.isEmpty
    }

    func count(for kind: FavoriteKind) -> Int {
        favorites.filter { $0.kind == kind }.count
    }
}

private func cleanedArtist(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t.isEmpty || t == "Unknown" || t == "Various" { return nil }
    return t
}
