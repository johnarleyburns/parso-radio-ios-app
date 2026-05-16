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
