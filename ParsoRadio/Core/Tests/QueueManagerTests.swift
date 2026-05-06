import XCTest
@testable import ParsoRadio

final class QueueManagerTests: XCTestCase {
    private var db: DatabaseService!
    private var queue: QueueManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService(path: ":memory:")
        queue = QueueManager(db: db)
    }

    func testNextTrackReturnsMatchingTrack() throws {
        seedTracks(composer: "bach", instrument: "strings", count: 5)

        let channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        let track = queue.nextTrack(channel: channel)
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.composer, "bach")
    }

    func testNoRepeatWithin50Plays() throws {
        seedTracks(composer: "chopin", instrument: "piano", count: 10)
        let channel = Channel.defaults.first { $0.id == "chopin-rachmaninoff-piano" }!

        var seen: Set<String> = []
        for _ in 0..<10 {
            guard let t = queue.nextTrack(channel: channel) else { break }
            XCTAssertFalse(seen.contains(t.id), "Track \(t.id) repeated")
            seen.insert(t.id)
        }
    }

    func testReturnsNilWhenPoolEmpty() throws {
        let channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        XCTAssertNil(queue.nextTrack(channel: channel))
    }

    func testExpandsToSimilarComposersWhenPoolThin() throws {
        // Only 3 Bach tracks — below the 20-track threshold
        seedTracks(composer: "bach",    instrument: "strings", count: 3)
        // Add Handel tracks (similar to Bach)
        seedTracks(composer: "handel",  instrument: "strings", count: 5, prefix: "handel")

        let channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!
        var results: [Track] = []
        for _ in 0..<8 {
            if let t = queue.nextTrack(channel: channel) { results.append(t) }
        }
        // Should draw from both Bach and expanded Handel pool
        XCTAssertGreaterThan(results.count, 3)
    }

    func testDeterministicOrderIsSameForSameDay() throws {
        seedTracks(composer: "bach", instrument: "strings", count: 20)
        let channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" }!

        let q1 = QueueManager(db: db)
        let q2 = QueueManager(db: db)

        let t1 = q1.nextTrack(channel: channel)
        let t2 = q2.nextTrack(channel: channel)
        XCTAssertEqual(t1?.id, t2?.id)
    }

    // MARK: - Helpers

    private func seedTracks(composer: String, instrument: String, count: Int, prefix: String? = nil) {
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
        db.saveTracks(tracks)
        Thread.sleep(forTimeInterval: 0.1)
    }
}
