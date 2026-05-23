import XCTest
@testable import ParsoMusic

final class QueueManagerTests: XCTestCase {
    private var db: DatabaseService!
    private var queue: QueueManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        queue = QueueManager(db: db)
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

        let q1 = QueueManager(db: db)
        let q2 = QueueManager(db: db)

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
        let sg = Channel.defaults.first { $0.id == "guitar-classical" }!
        let cm = Channel.defaults.first { $0.id == "chamber-music" }!
        var all: [Track] = []
        for i in 1...5 { all.append(makeStamped(id: "sg-\(i)", stamp: "guitar-classical")) }
        for i in 1...5 { all.append(makeStamped(id: "cm-\(i)", stamp: "chamber-music")) }
        await db.saveTracks(all)

        // Drain Classical Guitar far past its 5-track pool to force the
        // exhausted -> reset -> re-fetch loop. It must only ever return its
        // own stamped tracks.
        for _ in 0..<30 {
            guard let t = await queue.nextTrack(channel: sg, shuffleMode: false) else {
                XCTFail("Classical Guitar pool should loop, not run dry"); return
            }
            XCTAssertTrue(t.id.hasPrefix("sg-"),
                "Classical Guitar leaked a non-classical-guitar track: \(t.id)")
        }
        // Chamber Music's pool must be its full 5 — NOT shrunk by Spanish
        // Guitar's per-channel history.
        var cmSeen = Set<String>()
        for _ in 0..<5 {
            guard let t = await queue.nextTrack(channel: cm, shuffleMode: false) else { break }
            XCTAssertTrue(t.id.hasPrefix("cm-"), "Chamber Music returned a foreign track: \(t.id)")
            cmSeen.insert(t.id)
        }
        XCTAssertEqual(cmSeen.count, 5,
            "Chamber Music pool must be independent of Classical Guitar history")
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

    private func makeStamped(id: String, stamp: String) -> Track {
        Track(
            id: id, source: "internet_archive",
            title: "T \(id)", artist: "Various",
            duration: 180,
            streamURL: URL(string: "https://archive.org/download/\(id)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: ["classical", Channel.stampToken(stamp)],
            qualityScore: 1.0,
            rawCreator: "", composer: nil, instruments: [],
            metadataConfidence: 0.0
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
}
