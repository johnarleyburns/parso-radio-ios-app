import XCTest
@testable import ParsoMusic

final class QueueManagerTests: XCTestCase {
    private var db: DatabaseService!
    private var queue: QueueManager!
    // Isolated, freshly-cleared defaults so the persisted "shadow recently
    // played" can't leak between test methods (or from a prior run).
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        let suite = "QueueManagerTests"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        queue = QueueManager(db: db, defaults: defaults)
    }

    func testNextTrackReturnsMatchingTrack() async throws {
        await seedTracks(composer: "bach", instrument: "strings", count: 5)

        let channel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
        let track = await queue.nextTrack(channel: channel, shuffleMode: true)
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.composer, "bach")
    }

    func testNoRepeatWithin50Plays() async throws {
        await seedTracks(composer: "chopin", instrument: "piano", count: 10)
        let channel = Channel(id: "chopin", name: "Chopin", category: "Classical", icon: "pianokeys", composers: ["chopin"], preferredSource: "internet_archive")

        var seen: Set<String> = []
        for _ in 0..<10 {
            guard let t = await queue.nextTrack(channel: channel, shuffleMode: true) else { break }
            XCTAssertFalse(seen.contains(t.id), "Track \(t.id) repeated")
            seen.insert(t.id)
        }
    }

    func testReturnsNilWhenPoolEmpty() async throws {
        let channel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
        let track = await queue.nextTrack(channel: channel, shuffleMode: true)
        XCTAssertNil(track)
    }

    func testExpandsToSimilarComposersWhenPoolThin() async throws {
        // Only 3 Bach tracks — below the 20-track threshold
        await seedTracks(composer: "bach",   instrument: "strings", count: 3)
        // Handel is in Bach's similarity list
        await seedTracks(composer: "handel", instrument: "strings", count: 5, prefix: "handel")

        let channel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
        var results: [Track] = []
        for _ in 0..<8 {
            if let t = await queue.nextTrack(channel: channel, shuffleMode: true) { results.append(t) }
        }
        XCTAssertGreaterThan(results.count, 3)
    }

    func testDeterministicOrderIsSameForSameDay() async throws {
        await seedTracks(composer: "bach", instrument: "strings", count: 20)
        let channel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")

        let q1 = QueueManager(db: db, defaults: defaults)
        let q2 = QueueManager(db: db, defaults: defaults)

        let t1 = await q1.nextTrack(channel: channel, shuffleMode: true)
        let t2 = await q2.nextTrack(channel: channel, shuffleMode: true)
        XCTAssertEqual(t1?.id, t2?.id)
    }

    // Lecture channels aggregate a whole faculty — they must ALWAYS shuffle
    // regardless of the global toggle. Asserted via the pure decision
    // (QueueManager.usesShuffle) so it can't flake on a seeded-RNG
    // permutation that coincidentally equals sorted order; plus a
    // deterministic drain to prove the whole pool stays reachable.
    func testLectureChannelAlwaysShuffles() async throws {
        let lecture = Channel(
            id: "oxford-philosophy", name: "Philosophy", category: "Lectures",
            icon: "quote.bubble", tags: ["faculty-philosophy"],
            contentType: .spokenWord, preferredSource: "oxford_lectures"
        )
        XCTAssertTrue(QueueManager.usesShuffle(channel: lecture, shuffleMode: false),
            "Lecture channel must shuffle even with the toggle OFF")
        XCTAssertTrue(QueueManager.usesShuffle(channel: lecture, shuffleMode: true))

        // Control: a plain non-registry tag channel follows the toggle.
        let tagCh = Channel(id: "x", name: "x", category: "Contemporary",
                            icon: "x", tags: ["jazz"], preferredSource: "fma")
        XCTAssertFalse(QueueManager.usesShuffle(channel: tagCh, shuffleMode: false))
        XCTAssertTrue(QueueManager.usesShuffle(channel: tagCh, shuffleMode: true))

        // Deterministic drain: regardless of order, the whole pool is reachable.
        var tracks: [Track] = []
        for i in 1...8 {
            tracks.append(Track(
                id: "oxford-\(i)", source: "oxford_lectures",
                title: "Lecture \(i)", artist: "University of Oxford",
                duration: 600,
                streamURL: URL(string: "https://podcasts.ox.ac.uk/x/\(i)")!,
                downloadURL: nil, localFilePath: nil,
                license: .ccBy, tags: ["oxford-lectures", "faculty-philosophy"],
                qualityScore: 1.0,
                rawCreator: "University of Oxford", composer: nil, instruments: [],
                metadataConfidence: 2.0
            ))
        }
        await db.saveTracks(tracks)
        var seen = Set<String>()
        for _ in 0..<8 {
            guard let t = await queue.nextTrack(channel: lecture, shuffleMode: false) else { break }
            seen.insert(t.id)
        }
        XCTAssertEqual(seen, Set(tracks.map(\.id)), "every lecture must be reachable")
    }

    // Channel leakage regression: draining a curated channel past its pool
    // (forcing the exhausted-loop path) must NEVER surface another channel's
    // tracks, and one channel's play history must not shrink another's pool.
    func testCuratedChannelsDoNotLeakAcrossEachOther() async throws {
        // Curated-category channels are now MANIFEST-ONLY (no search-pool
        // fallback). The "no leak across channels" property is now enforced by
        // the per-channel manifest entries being separate — exercise that path
        // by injecting a manifestPool keyed by channel id.
        let sg = Channel.defaults.first { $0.id == "guitar-classical" }!
        let cm = Channel.defaults.first { $0.id == "string-quartet" }!
        let sgApproved = (1...5).map { makeStamped(id: "sg-\($0)", stamp: "x") }
        let cmApproved = (1...5).map { makeStamped(id: "cm-\($0)", stamp: "x") }
        await db.saveTracks(sgApproved + cmApproved)
        let q = QueueManager(db: db, defaults: defaults, manifestPool: { channelId in
            switch channelId {
            case "guitar-classical": return sgApproved
            case "string-quartet":    return cmApproved
            default:                  return []
            }
        })

        // Drain Classical Guitar far past its 5-track pool — it must only ever
        // return tracks from its OWN manifest entry, never leak across.
        for _ in 0..<30 {
            guard let t = await q.nextTrack(channel: sg, shuffleMode: false) else {
                XCTFail("Classical Guitar pool should loop, not run dry"); return
            }
            XCTAssertTrue(t.id.hasPrefix("sg-"),
                "Classical Guitar leaked a non-classical-guitar track: \(t.id)")
        }
        var cmSeen = Set<String>()
        for _ in 0..<5 {
            guard let t = await q.nextTrack(channel: cm, shuffleMode: false) else { break }
            XCTAssertTrue(t.id.hasPrefix("cm-"), "Chamber Music returned a foreign track: \(t.id)")
            cmSeen.insert(t.id)
        }
        XCTAssertEqual(cmSeen.count, 5,
            "Chamber Music pool must be independent of Classical Guitar history")
    }

    // Curated channels are MANIFEST-ONLY: when the manifest entry is empty, the
    // channel returns nil (NOT the search pool). This is the explicit "die on
    // the curated-quality hill" + live-curation-feedback policy. Non-Curated
    // channels keep falling back to the search pool.
    func testCuratedChannelReturnsNilWhenManifestEmpty() async throws {
        let sg = Channel.defaults.first { $0.id == "guitar-classical" }!
        // Seed a stamped DB track that WOULD show up via the old search pool.
        await db.saveTracks([makeStamped(id: "sg-1", stamp: "guitar-classical")])
        let q = QueueManager(db: db, defaults: defaults,
                             manifestPool: { _ in [] })   // empty manifest
        let t = await q.nextTrack(channel: sg, shuffleMode: true)
        XCTAssertNil(t,
            "Curated channel with empty manifest must NOT fall back to the search pool — manifest-only is the explicit policy")
    }

    // Item 7: confirmed album/book items are weighted higher so they surface
    // more often than one-off single tracks in curated channels.
    func testAlbumItemsAreWeightedHigher() {
        func track(_ id: String, multi: Bool?) -> Track {
            Track(id: id, source: "internet_archive", title: id, artist: "a",
                  duration: 1,
                  streamURL: URL(string: "https://archive.org/download/\(id)")!,
                  downloadURL: nil, localFilePath: nil,
                  license: .publicDomain, tags: [], qualityScore: 1.0,
                  rawCreator: "", composer: nil, instruments: [],
                  metadataConfidence: 1.0, isMultiPart: multi)
        }
        let single  = QueueManager.selectionWeight(track("s", multi: false))
        let unknown = QueueManager.selectionWeight(track("u", multi: nil))
        let album   = QueueManager.selectionWeight(track("a", multi: true))

        XCTAssertEqual(single, unknown, accuracy: 1e-9,
            "nil (unprobed) and false stay neutral")
        XCTAssertEqual(album, single * QueueManager.albumBoost, accuracy: 1e-9,
            "confirmed album/book items get the album boost")
        XCTAssertGreaterThan(album, single, "albums must out-weigh singles")
    }

    // MARK: - Helpers

    private func makeStamped(id: String, stamp: String,
                              partNumber: Int? = nil,
                              parentIdentifier: String? = nil) -> Track {
        Track(
            id: id, source: "internet_archive",
            title: "T \(id)", artist: "Various",
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: ["classical", Channel.stampToken(stamp)],
            qualityScore: 1.0,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 0.0,
            partNumber: partNumber, parentIdentifier: parentIdentifier
        )
    }

    private func seedTracks(composer: String, instrument: String, count: Int, prefix: String? = nil) async {
        let p = prefix ?? composer
        let tracks = (0..<count).map { i in
            Track(
                id: "\(p)-\(i)", source: "internet_archive",
                title: "Track \(i)", artist: composer,
                duration: 180,
                streamURL: URL(string: "https://archive.org/download/\(p)-\(i)")!,
                downloadURL: nil, localFilePath: nil,
                license: .publicDomain, tags: [],
                qualityScore: 0.8,
                rawCreator: composer,
                composer: composer,
                instruments: [instrument],
                metadataConfidence: 3.0
            )
        }
        await db.saveTracks(tracks)
    }

    // MARK: - Curated channel approval enforcement (Fix B)

    /// `nextPart` on a curated channel must return only approved tracks,
    /// filtering out stamped-but-unapproved siblings of the same parent.
    func testNextPartReturnsOnlyApprovedTracks() async throws {
        let stamp = Channel.stampToken("guitar-classical")
        let tracks = [
            makeStamped(id: "sg-p1", stamp: "guitar-classical",
                        partNumber: 1, parentIdentifier: "album-abc"),
            makeStamped(id: "sg-p2", stamp: "guitar-classical",
                        partNumber: 2, parentIdentifier: "album-abc"),
        ]
        await db.saveTracks(tracks)
        // Only p1 is "approved"
        let q = QueueManager(db: db, defaults: defaults, manifestPool: { _ in
            tracks.filter { $0.id == "sg-p1" }
        })
        let sg = Channel.defaults.first { $0.id == "guitar-classical" }!

        let next = await q.nextPart(after: tracks[0], channel: sg)
        // sg-p2 is stamped but NOT approved — it's filtered out by approvedFilter.
        // The fallback (last part → nextBook) wraps to the only approved track (sg-p1).
        // The key invariant: sg-p2 is NEVER returned because it's not approved.
        XCTAssertNotNil(next)
        XCTAssertNotEqual(next?.id, "sg-p2",
            "Unapproved sibling track must NEVER be returned by nextPart")
    }

    /// `previousPart` must also filter to approved-only for curated channels.
    func testPreviousPartReturnsOnlyApprovedTracks() async throws {
        let tracks = [
            makeStamped(id: "sg-q1", stamp: "guitar-classical",
                        partNumber: 1, parentIdentifier: "album-xyz"),
            makeStamped(id: "sg-q2", stamp: "guitar-classical",
                        partNumber: 2, parentIdentifier: "album-xyz"),
        ]
        await db.saveTracks(tracks)
        // Only q2 is "approved"
        let q = QueueManager(db: db, defaults: defaults, manifestPool: { _ in
            tracks.filter { $0.id == "sg-q2" }
        })
        let sg = Channel.defaults.first { $0.id == "guitar-classical" }!

        let prev = await q.previousPart(before: tracks[1], channel: sg)
        // sg-q1 is stamped but NOT approved — must NOT be returned
        XCTAssertNil(prev,
            "Part navigation must NOT return unapproved previous parts on curated channels")
    }

    /// Non-curated channels (e.g. LibriVox audiobooks) must NOT be affected
    /// by the approval filter — they should still return all stamped tracks.
    func testNextPartUnfilteredForNonCuratedChannel() async throws {
        let tracks = [
            makeStamped(id: "lv-ch1", stamp: "lv-science-fiction",
                        partNumber: 1, parentIdentifier: "lv-book-1"),
            makeStamped(id: "lv-ch2", stamp: "lv-science-fiction",
                        partNumber: 2, parentIdentifier: "lv-book-1"),
        ]
        await db.saveTracks(tracks)
        // Empty manifest (non-curated channel)
        let q = QueueManager(db: db, defaults: defaults, manifestPool: { _ in [] })
        let lv = Channel.defaults.first { $0.id == "lv-science-fiction" }!

        let next = await q.nextPart(after: tracks[0], channel: lv)
        // lv-arts is Audiobooks category (NOT Curated) — all tracks should be visible
        XCTAssertNotNil(next,
            "Non-Curated audiobook channels must NOT be affected by approval filter")
        XCTAssertEqual(next?.id, "lv-ch2")
    }
}
