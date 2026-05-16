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

    // Lecture channels aggregate a whole faculty — they must play in random
    // order even with the global shuffle toggle OFF (Oxford tracks carry no
    // addedDate, so the non-shuffle path would emit an arbitrary order anyway).
    func testLectureChannelPlaysRandomOrderWithShuffleOff() async throws {
        let slug = "faculty-philosophy"
        var tracks: [Track] = []
        for i in 1...8 {
            var t = Track(
                id: "oxford-\(i)", source: "oxford_lectures",
                title: "Lecture \(i)", artist: "University of Oxford",
                duration: 600,
                streamURL: URL(string: "https://podcasts.ox.ac.uk/x/\(i)")!,
                downloadURL: nil, localFilePath: nil,
                license: .ccBy, tags: ["oxford-lectures", slug],
                qualityScore: 1.0,
                rawCreator: "University of Oxford", composer: nil, instruments: [],
                metadataConfidence: 2.0
            )
            t.addedDate = Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + i * 86_400))
            tracks.append(t)
        }
        await db.saveTracks(tracks)

        let channel = Channel(
            id: "oxford-philosophy", name: "Philosophy", category: "Lectures",
            icon: "quote.bubble", tags: [slug],
            contentType: .spokenWord, preferredSource: "oxford_lectures"
        )
        var order: [String] = []
        for _ in 0..<8 {
            guard let t = await queue.nextTrack(channel: channel, shuffleMode: false) else { break }
            order.append(t.id)
        }
        let strictNewestFirst = tracks
            .sorted { ($0.addedDate ?? .distantPast) > ($1.addedDate ?? .distantPast) }
            .map(\.id)

        XCTAssertEqual(order.count, 8, "queue should drain the lecture pool")
        XCTAssertEqual(Set(order), Set(strictNewestFirst), "every lecture must be reachable")
        XCTAssertNotEqual(order, strictNewestFirst,
            "Lecture channel must be randomized, not strict newest-first, with shuffle off")
    }

    // MARK: - Helpers

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
