import XCTest
@testable import ParsoMusic

// MARK: - Favorite Model Tests

final class FavoriteModelTests: XCTestCase {

    func testFavoriteKindRawValues() {
        XCTAssertEqual(FavoriteKind.track.rawValue, "track")
        XCTAssertEqual(FavoriteKind.book.rawValue, "book")
        XCTAssertEqual(FavoriteKind.episode.rawValue, "episode")
        XCTAssertEqual(FavoriteKind.lecture.rawValue, "lecture")
    }

    func testFavoriteKindAllCases() {
        let cases = FavoriteKind.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertTrue(cases.contains(.track))
        XCTAssertTrue(cases.contains(.book))
        XCTAssertTrue(cases.contains(.episode))
        XCTAssertTrue(cases.contains(.lecture))
    }

    func testFavoriteIdentifiable() {
        let fav = Favorite(
            id: "test-id", kind: .track, dateAdded: Date(),
            title: "Test", creator: nil, artworkURL: nil,
            sourceIdentifier: "src", resumePoint: nil
        )
        XCTAssertEqual(fav.id, "test-id")
    }

    func testResumePointEquatable() {
        let rp1 = ResumePoint(chapterIndex: 1, positionSeconds: 42.5,
                              updatedAt: Date(timeIntervalSince1970: 1000))
        let rp2 = ResumePoint(chapterIndex: 1, positionSeconds: 42.5,
                              updatedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(rp1, rp2)
    }

    func testResumePointNotEqualDifferentChapter() {
        let now = Date()
        let rp1 = ResumePoint(chapterIndex: 1, positionSeconds: 42.5, updatedAt: now)
        let rp2 = ResumePoint(chapterIndex: 2, positionSeconds: 42.5, updatedAt: now)
        XCTAssertNotEqual(rp1, rp2)
    }

    func testResumePointNotEqualDifferentPosition() {
        let now = Date()
        let rp1 = ResumePoint(chapterIndex: 1, positionSeconds: 42.5, updatedAt: now)
        let rp2 = ResumePoint(chapterIndex: 1, positionSeconds: 99.0, updatedAt: now)
        XCTAssertNotEqual(rp1, rp2)
    }
}

// MARK: - Content Type Resolution Tests

final class ContentTypeResolutionTests: XCTestCase {

    func testPodcastSourceResolvesToEpisode() {
        let track = makeTrack(id: "pod-1", source: "podcast")
        let ch = Channel.defaults.first { $0.category == "Podcasts" }
        XCTAssertEqual(track.resolveContentType(channel: ch), .podcastEpisode)
        XCTAssertEqual(track.favoriteKind(channel: ch), .episode)
    }

    func testOxfordLectureResolvesToLecture() {
        let track = makeTrack(id: "ox-1", source: "oxford_lectures")
        XCTAssertEqual(track.resolveContentType(channel: nil), .lecture)
        XCTAssertEqual(track.favoriteKind(channel: nil), .lecture)
    }

    func testAudiobookChannelResolvesToBook() {
        let ch = Channel(id: "lv-test", name: "Test Books", category: "Audiobooks",
                         icon: "book", contentType: .spokenWord,
                         preferredSource: "internet_archive")
        let track = makeTrack(id: "lv-test/chap1.mp3", source: "internet_archive",
                              partNum: 1, totalParts: 10, parentId: "lv-test")
        XCTAssertEqual(track.resolveContentType(channel: ch), .audiobook)
        XCTAssertEqual(track.favoriteKind(channel: ch), .book)
    }

    func testAudiobookChannelWithParentResolvesToBook() {
        let ch = Channel(id: "lv-general-fiction", name: "General Fiction",
                         category: "Audiobooks", icon: "books.vertical",
                         contentType: .spokenWord, preferredSource: "internet_archive")
        let track = makeTrack(id: "lv-general-fiction/chap1.mp3", source: "internet_archive",
                              partNum: 1, totalParts: 10, parentId: "lv-general-fiction")
        XCTAssertEqual(track.resolveContentType(channel: ch), .audiobook)
        XCTAssertEqual(track.favoriteKind(channel: ch), .book)
    }

    func testMusicTrackDefaultsToMusic() {
        let ch = Channel(id: "test-music", name: "Test Music", category: "Curated Music",
                         icon: "pianokeys", contentType: .music,
                         preferredSource: "internet_archive")
        let track = makeTrack(id: "music-1", source: "internet_archive",
                              composer: "Beethoven")
        XCTAssertEqual(track.resolveContentType(channel: ch), .musicTrack)
        XCTAssertEqual(track.favoriteKind(channel: ch), .track)
    }

    func testMusicAlbumTrackStaysMusic() {
        let ch = Channel(id: "test-orchestra", name: "Test Orchestra",
                         category: "Curated Music", icon: "music.note.list",
                         contentType: .music, preferredSource: "internet_archive")
        let track = makeTrack(id: "symph-album/track1.mp3", source: "internet_archive",
                              partNum: 1, totalParts: 4, parentId: "symph-album",
                              composer: "Mahler")
        XCTAssertEqual(track.resolveContentType(channel: ch), .musicTrack)
        XCTAssertEqual(track.favoriteKind(channel: ch), .track)
    }

    func testUnknownContentDefaultsToMusic() {
        let track = makeTrack(id: "unknown-1", source: "fma")
        XCTAssertEqual(track.resolveContentType(channel: nil), .musicTrack)
        XCTAssertEqual(track.favoriteKind(channel: nil), .track)
    }
}

// MARK: - Favorite ID Tests

final class FavoriteIDTests: XCTestCase {

    func testTrackFavoriteIDIsTrackID() {
        let track = makeTrack(id: "ia-item/file.mp3", source: "internet_archive")
        XCTAssertEqual(track.favoriteID(for: .track), "ia-item/file.mp3")
    }

    func testBookFavoriteIDIsParentIdentifier() {
        let track = makeTrack(id: "book123/chapter5.mp3", source: "internet_archive",
                              partNum: 5, totalParts: 12, parentId: "book123")
        XCTAssertEqual(track.favoriteID(for: .book), "book123")
    }

    func testBookFavoriteIDFallsBackToTrackID() {
        let track = makeTrack(id: "solo-book.mp3", source: "internet_archive")
        XCTAssertEqual(track.favoriteID(for: .book), "solo-book.mp3")
    }

    func testEpisodeFavoriteIDIsTrackID() {
        let track = makeTrack(id: "podcast/ep-42.mp3", source: "podcast")
        XCTAssertEqual(track.favoriteID(for: .episode), "podcast/ep-42.mp3")
    }

    func testLectureFavoriteIDIsTrackID() {
        let track = makeTrack(id: "ox-physics/lecture-7.mp3", source: "oxford_lectures")
        XCTAssertEqual(track.favoriteID(for: .lecture), "ox-physics/lecture-7.mp3")
    }
}

// MARK: - Database Favorites CRUD Tests

final class FavoritesDatabaseTests: XCTestCase {
    private var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
    }

    override func tearDownWithError() throws {
        db = nil
        try super.tearDownWithError()
    }

    func testSaveAndFetchAll() async throws {
        await db.saveFavorite(makeFav(id: "fav-1", kind: .track, title: "Song 1"))
        let all = await db.fetchAllFavorites()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, "fav-1")
        XCTAssertEqual(all.first?.kind, .track)
        XCTAssertEqual(all.first?.title, "Song 1")
    }

    func testFetchByKind() async throws {
        await db.saveFavorite(makeFav(id: "t1", kind: .track, title: "Track"))
        await db.saveFavorite(makeFav(id: "b1", kind: .book, title: "Book"))
        await db.saveFavorite(makeFav(id: "e1", kind: .episode, title: "Episode"))
        await db.saveFavorite(makeFav(id: "l1", kind: .lecture, title: "Lecture"))
        let tracks = await db.fetchFavorites(ofKind: .track)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.id, "t1")
        let books = await db.fetchFavorites(ofKind: .book)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.id, "b1")
    }

    func testIsFavorited() async throws {
        var isFav = await db.isFavorited(id: "fav-x")
        XCTAssertFalse(isFav)
        await db.saveFavorite(makeFav(id: "fav-x", kind: .track, title: "X"))
        isFav = await db.isFavorited(id: "fav-x")
        XCTAssertTrue(isFav)
    }

    func testFetchFavoriteById() async throws {
        let fav = makeFav(id: "fav-single", kind: .book, title: "Book Title",
                          creator: "Author", resumePoint: ResumePoint(
                            chapterIndex: 3, positionSeconds: 120,
                            updatedAt: Date(timeIntervalSince1970: 5000)))
        await db.saveFavorite(fav)
        let loaded = await db.fetchFavorite(id: "fav-single")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "Book Title")
        XCTAssertEqual(loaded?.creator, "Author")
        XCTAssertEqual(loaded?.resumePoint?.chapterIndex, 3)
        XCTAssertEqual(loaded?.resumePoint?.positionSeconds, 120)
        XCTAssertEqual(loaded?.resumePoint?.updatedAt.timeIntervalSince1970, 5000)
    }

    func testDeleteFavorite() async throws {
        await db.saveFavorite(makeFav(id: "to-delete", kind: .track, title: "Del"))
        var isFav = await db.isFavorited(id: "to-delete")
        XCTAssertTrue(isFav)
        await db.deleteFavorite(id: "to-delete")
        isFav = await db.isFavorited(id: "to-delete")
        XCTAssertFalse(isFav)
    }

    func testDeleteNonExistentIsNoop() async throws {
        await db.deleteFavorite(id: "does-not-exist")
        let isFav = await db.isFavorited(id: "does-not-exist")
        XCTAssertFalse(isFav)
    }

    func testUpdateResumePoint() async throws {
        await db.saveFavorite(makeFav(id: "book-rp", kind: .book, title: "Book"))
        let rp = ResumePoint(chapterIndex: 5, positionSeconds: 300,
                             updatedAt: Date(timeIntervalSince1970: 9999))
        await db.updateResumePoint(favoriteId: "book-rp", resumePoint: rp)
        let loaded = await db.fetchFavorite(id: "book-rp")
        XCTAssertEqual(loaded?.resumePoint?.chapterIndex, 5)
        XCTAssertEqual(loaded?.resumePoint?.positionSeconds, 300)
    }

    func testFavoriteCount() async throws {
        var count = await db.favoriteCount()
        XCTAssertEqual(count, 0)
        await db.saveFavorite(makeFav(id: "c1", kind: .track, title: "T1"))
        await db.saveFavorite(makeFav(id: "c2", kind: .book, title: "B1"))
        count = await db.favoriteCount()
        XCTAssertEqual(count, 2)
    }

    func testFavoriteCountByKind() async throws {
        await db.saveFavorite(makeFav(id: "ck1", kind: .track, title: "T1"))
        await db.saveFavorite(makeFav(id: "ck2", kind: .track, title: "T2"))
        await db.saveFavorite(makeFav(id: "ck3", kind: .book, title: "B1"))
        let trackCount = await db.favoriteCount(ofKind: .track)
        let bookCount = await db.favoriteCount(ofKind: .book)
        let epCount = await db.favoriteCount(ofKind: .episode)
        XCTAssertEqual(trackCount, 2)
        XCTAssertEqual(bookCount, 1)
        XCTAssertEqual(epCount, 0)
    }

    func testSavingSameIDTwiceUpdates() async throws {
        let fav1 = makeFav(id: "dup-id", kind: .track, title: "Original")
        await db.saveFavorite(fav1)
        let fav2 = makeFav(id: "dup-id", kind: .track, title: "Updated",
                           dateAdded: Date(timeIntervalSince1970: 2000))
        await db.saveFavorite(fav2)
        let loaded = await db.fetchFavorite(id: "dup-id")
        XCTAssertEqual(loaded?.title, "Updated")
        let count = await db.favoriteCount()
        XCTAssertEqual(count, 1)
    }

    func testFavoritesSortedByDateDescending() async throws {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let t3 = Date(timeIntervalSince1970: 3000)
        await db.saveFavorite(makeFav(id: "oldest", kind: .track, title: "Old", dateAdded: t1))
        await db.saveFavorite(makeFav(id: "mid", kind: .track, title: "Mid", dateAdded: t2))
        await db.saveFavorite(makeFav(id: "newest", kind: .track, title: "New", dateAdded: t3))
        let all = await db.fetchAllFavorites()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].id, "newest")
        XCTAssertEqual(all[1].id, "mid")
        XCTAssertEqual(all[2].id, "oldest")
    }

    func testSaveWithResumePoint() async throws {
        let rp = ResumePoint(chapterIndex: 2, positionSeconds: 90,
                             updatedAt: Date(timeIntervalSince1970: 7000))
        await db.saveFavorite(makeFav(id: "with-rp", kind: .book, title: "Book", resumePoint: rp))
        let loaded = await db.fetchFavorite(id: "with-rp")
        XCTAssertEqual(loaded?.resumePoint?.chapterIndex, 2)
        XCTAssertEqual(loaded?.resumePoint?.positionSeconds, 90)
    }

    func testSaveWithoutResumePoint() async throws {
        await db.saveFavorite(makeFav(id: "no-rp", kind: .track, title: "Track"))
        let loaded = await db.fetchFavorite(id: "no-rp")
        XCTAssertNil(loaded?.resumePoint)
    }

    func testArtworkURLRoundTrip() async throws {
        let url = URL(string: "https://archive.org/services/img/test-item")
        let fav = Favorite(id: "art-test", kind: .track, dateAdded: Date(),
                           title: "Art", creator: nil, artworkURL: url,
                           sourceIdentifier: "test-item", resumePoint: nil)
        await db.saveFavorite(fav)
        let loaded = await db.fetchFavorite(id: "art-test")
        XCTAssertEqual(loaded?.artworkURL, url)
    }
}

// MARK: - FavoritesStore Tests

@MainActor
final class FavoritesStoreTests: XCTestCase {
    private var db: DatabaseService!
    private var store: FavoritesStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        store = FavoritesStore(db: db)
    }

    override func tearDownWithError() throws {
        store = nil
        db = nil
        try super.tearDownWithError()
    }

    func testToggleFavoriteMusicTrack() async throws {
        let ch = musicChannel()
        await db.saveTracks([sampleMusicTrack()])
        let track = sampleMusicTrack()
        await store.toggle(track: track, channel: ch)
        await store.loadAll()
        let isFav = await store.isFavorited(track: track, channel: ch)
        XCTAssertTrue(isFav)
        XCTAssertEqual(store.songs().count, 1)
        XCTAssertEqual(store.books().count, 0)
    }

    func testToggleUnfavoriteMusicTrack() async throws {
        let ch = musicChannel()
        let track = sampleMusicTrack()
        await store.toggle(track: track, channel: ch)
        await store.loadAll()
        XCTAssertEqual(store.songs().count, 1)
        await store.toggle(track: track, channel: ch)
        await store.loadAll()
        XCTAssertEqual(store.songs().count, 0)
        let isFav = await store.isFavorited(track: track, channel: ch)
        XCTAssertFalse(isFav)
    }

    func testToggleAudiobookPromotesToBook() async throws {
        let ch = bookChannel()
        let track = sampleChapter(parentId: "great-book", partNum: 5)
        await store.toggle(track: track, channel: ch)
        await store.loadAll()
        XCTAssertEqual(store.books().count, 1)
        XCTAssertEqual(store.songs().count, 0)
        let book = store.books().first!
        XCTAssertEqual(book.id, "great-book")
    }

    func testFavoritingAudiobookChapterShowsHeartOnAllChapters() async throws {
        let ch = bookChannel()
        let chapter3 = sampleChapter(parentId: "moby-dick", partNum: 3)
        let chapter7 = sampleChapter(parentId: "moby-dick", partNum: 7)
        await store.toggle(track: chapter3, channel: ch)
        await store.loadAll()
        let isFav3 = await store.isFavorited(track: chapter3, channel: ch)
        let isFav7 = await store.isFavorited(track: chapter7, channel: ch)
        XCTAssertTrue(isFav3)
        XCTAssertTrue(isFav7)
    }

    func testAudiobookResumePointCapturedOnFavorite() async throws {
        let ch = bookChannel()
        let track = sampleChapter(parentId: "war-peace", partNum: 12)
        await store.toggle(track: track, channel: ch, positionSeconds: 345.0, chapterIndex: 12)
        await store.loadAll()
        let book = store.books().first!
        XCTAssertEqual(book.resumePoint?.positionSeconds, 345.0)
        XCTAssertEqual(book.resumePoint?.chapterIndex, 12)
    }

    func testAudiobookResumePointNotSetWithoutPosition() async throws {
        let ch = bookChannel()
        let track = sampleChapter(parentId: "book-np", partNum: 1)
        await store.toggle(track: track, channel: ch, positionSeconds: nil)
        await store.loadAll()
        let book = store.books().first!
        XCTAssertNil(book.resumePoint)
    }

    func testPodcastEpisodeFavorite() async throws {
        let ch = Channel(id: "news-test", name: "News", category: "Podcasts",
                         icon: "radio", contentType: .spokenWord,
                         preferredSource: "podcast")
        let track = makeTrack(id: "podcast-show/ep-42.mp3", source: "podcast",
                              duration: 1800)
        await store.toggle(track: track, channel: ch, positionSeconds: 600)
        await store.loadAll()
        XCTAssertEqual(store.episodes().count, 1)
        XCTAssertEqual(store.episodes().first?.resumePoint?.positionSeconds, 600)
    }

    func testLectureFavorite() async throws {
        let track = makeTrack(id: "ox-maths/lec-1.mp3", source: "oxford_lectures",
                              duration: 3600)
        await store.toggle(track: track, channel: nil, positionSeconds: 120)
        await store.loadAll()
        XCTAssertEqual(store.lectures().count, 1)
        XCTAssertEqual(store.lectures().first?.resumePoint?.positionSeconds, 120)
        XCTAssertEqual(store.lectures().first?.id, "ox-maths/lec-1.mp3")
    }

    func testSameTrackFavoritedFromDifferentContextsIsOneEntry() async throws {
        let ch = musicChannel()
        let track = sampleMusicTrack()
        // Favorite from one context
        await store.toggle(track: track, channel: ch)
        await store.loadAll()
        XCTAssertEqual(store.songs().count, 1)
        // Now attempt to save same ID directly (simulating db-level dedup)
        let dupFav = Favorite(id: track.id, kind: .track, dateAdded: Date(),
                              title: track.title, creator: nil, artworkURL: nil,
                              sourceIdentifier: track.id, resumePoint: nil)
        await db.saveFavorite(dupFav)
        await store.loadAll()
        XCTAssertEqual(store.songs().count, 1,
                       "Dedup: same ID saved twice produces one entry (INSERT OR REPLACE)")
    }

    func testCountPerKind() async throws {
        let musicCh = musicChannel()
        let bookCh = bookChannel()
        await store.toggle(track: sampleMusicTrack(), channel: musicCh)
        await store.toggle(track: sampleChapter(parentId: "book-a", partNum: 1), channel: bookCh)
        await store.toggle(track: sampleChapter(parentId: "book-b", partNum: 1), channel: bookCh)
        await store.loadAll()
        XCTAssertEqual(store.count(for: .track), 1)
        XCTAssertEqual(store.count(for: .book), 2)
        XCTAssertEqual(store.count(for: .episode), 0)
        XCTAssertEqual(store.count(for: .lecture), 0)
    }

    func testHasAnyFavorites() async throws {
        XCTAssertFalse(store.hasAnyFavorites())
        await store.toggle(track: sampleMusicTrack(), channel: musicChannel())
        await store.loadAll()
        XCTAssertTrue(store.hasAnyFavorites())
    }

    func testStoreUpdateResumePoint() async throws {
        let ch = bookChannel()
        let track = sampleChapter(parentId: "book-rpu", partNum: 1)
        await store.toggle(track: track, channel: ch, positionSeconds: 10)
        await store.loadAll()
        let favId = track.favoriteID(for: .book)
        await store.updateResumePoint(forFavoriteId: favId, positionSeconds: 500,
                                      chapterIndex: 3)
        await store.loadAll()
        let updated = store.books().first { $0.id == favId }
        XCTAssertEqual(updated?.resumePoint?.positionSeconds, 500)
        XCTAssertEqual(updated?.resumePoint?.chapterIndex, 3)
    }
}

// MARK: - Acceptance Criteria Tests

@MainActor
final class FavoritesAcceptanceCriteriaTests: XCTestCase {
    private var db: DatabaseService!
    private var store: FavoritesStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        store = FavoritesStore(db: db)
    }

    override func tearDownWithError() throws {
        store = nil
        db = nil
        try super.tearDownWithError()
    }

    /// AC1: Tapping heart on music track adds/removes exactly that track under Songs
    func testAC1MusicTrackToggle() async throws {
        let ch = musicChannel()
        let track = sampleMusicTrack()
        await store.toggle(track: track, channel: ch)
        await store.loadAll()
        XCTAssertEqual(store.songs().count, 1)
        XCTAssertEqual(store.songs().first?.id, track.id)
        await store.toggle(track: track, channel: ch)
        await store.loadAll()
        XCTAssertEqual(store.songs().count, 0)
    }

    /// AC2: Tapping heart on audiobook chapter adds/removes the book under Books
    func testAC2AudiobookChapterTogglesBook() async throws {
        let ch = bookChannel()
        let chapter = sampleChapter(parentId: "moby-dick", partNum: 7)
        await store.toggle(track: chapter, channel: ch)
        await store.loadAll()
        XCTAssertEqual(store.books().count, 1)
        XCTAssertEqual(store.books().first?.id, "moby-dick")
        XCTAssertEqual(store.songs().count, 0)
        let chapter3 = sampleChapter(parentId: "moby-dick", partNum: 3)
        let isFav3 = await store.isFavorited(track: chapter3, channel: ch)
        XCTAssertTrue(isFav3)
        await store.toggle(track: chapter, channel: ch)
        await store.loadAll()
        XCTAssertEqual(store.books().count, 0)
        let isFav = await store.isFavorited(track: chapter, channel: ch)
        XCTAssertFalse(isFav)
    }

    /// AC6: Favoriting same item twice produces one entry (dedup via INSERT OR REPLACE)
    func testAC6DedupProducesOneEntry() async throws {
        let track = sampleMusicTrack()
        let fav1 = Favorite(id: track.id, kind: .track, dateAdded: Date(),
                            title: track.title, creator: nil,
                            artworkURL: nil, sourceIdentifier: track.id,
                            resumePoint: nil)
        await db.saveFavorite(fav1)
        let fav2 = Favorite(id: track.id, kind: .track,
                            dateAdded: Date(timeIntervalSince1970: 9999),
                            title: track.title, creator: nil,
                            artworkURL: nil, sourceIdentifier: track.id,
                            resumePoint: nil)
        await db.saveFavorite(fav2)
        await store.loadAll()
        XCTAssertEqual(store.songs().count, 1,
                       "Same ID favorited twice still produces 1 entry (INSERT OR REPLACE)")
        let count = await db.favoriteCount()
        XCTAssertEqual(count, 1)
    }

    /// AC7: Unfavoriting a book removes bookmark; re-favoriting starts fresh
    func testAC7ReFavoriteStartsFreshResumePoint() async throws {
        let ch = bookChannel()
        let chapter = sampleChapter(parentId: "re-fav-book", partNum: 5)
        await store.toggle(track: chapter, channel: ch, positionSeconds: 300, chapterIndex: 5)
        await store.loadAll()
        let firstFav = store.books().first!
        XCTAssertEqual(firstFav.resumePoint?.positionSeconds, 300)
        await store.toggle(track: chapter, channel: ch)
        await store.loadAll()
        XCTAssertEqual(store.books().count, 0)
        await store.toggle(track: chapter, channel: ch, positionSeconds: 100, chapterIndex: 2)
        await store.loadAll()
        let secondFav = store.books().first!
        XCTAssertEqual(secondFav.resumePoint?.positionSeconds, 100)
        XCTAssertEqual(secondFav.resumePoint?.chapterIndex, 2)
    }
}

// MARK: - Test Helpers

private func makeFav(id: String, kind: FavoriteKind, title: String,
                      creator: String? = nil, dateAdded: Date = Date(),
                      resumePoint: ResumePoint? = nil) -> Favorite {
    Favorite(id: id, kind: kind, dateAdded: dateAdded, title: title,
             creator: creator,
             artworkURL: URL(string: "https://archive.org/services/img/test"),
             sourceIdentifier: id, resumePoint: resumePoint)
}

private func makeTrack(id: String, source: String,
                        duration: Double = 100,
                        partNum: Int? = nil, totalParts: Int? = nil,
                        parentId: String? = nil,
                        composer: String? = nil) -> Track {
    Track(id: id, source: source, title: "Title", artist: "Artist",
          duration: duration,
          streamURL: URL(string: "https://example.com/\(id)")!,
          downloadURL: nil, license: .cc0, tags: [], qualityScore: 1,
          rawCreator: "", composer: composer, instruments: [],
          metadataConfidence: 1,
          partNumber: partNum, totalParts: totalParts,
          parentIdentifier: parentId)
}

private func sampleMusicTrack() -> Track {
    makeTrack(id: "piano-test/moonlight.mp3", source: "internet_archive",
              duration: 900, composer: "Beethoven")
}

private func sampleChapter(parentId: String, partNum: Int) -> Track {
    makeTrack(id: "\(parentId)/chapter\(partNum).mp3", source: "internet_archive",
              duration: 1800, partNum: partNum, totalParts: 20, parentId: parentId)
}

private func musicChannel() -> Channel {
    Channel(id: "test-music", name: "Test Music", category: "Curated Music",
            icon: "pianokeys", contentType: .music, preferredSource: "internet_archive")
}

private func bookChannel() -> Channel {
    Channel(id: "lv-fiction", name: "Fiction", category: "Audiobooks",
            icon: "book", contentType: .spokenWord, preferredSource: "internet_archive")
}
