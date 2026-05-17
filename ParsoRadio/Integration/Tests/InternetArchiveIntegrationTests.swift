import XCTest
@testable import ParsoMusic

// These tests hit the real Internet Archive API.
// URLErrors (network down, timeout) are skipped so CI isn't blocked by IA outages.
// Filtering failures (0 tracks returned despite a successful HTTP call) are hard
// failures — that's the bug class we want to catch.
final class InternetArchiveIntegrationTests: XCTestCase {

    private let service = InternetArchiveService()

    override func setUp() {
        super.setUp()
        // The parametrized registry test fetches ~28 channels live.
        executionTimeAllowance = 300
    }

    func testBachComposerChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel(id: "bach", name: "Bach", category: "Classical", icon: "music.note", composers: ["bach"], preferredSource: "internet_archive")
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(
                composers: channel.composers,
                instruments: channel.instruments
            )
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Bach composer: \(tracks.count) tracks passed filtering")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title) — instruments: \(t.instruments)")
        }
        XCTAssertFalse(
            tracks.isEmpty,
            "Expected ≥1 Bach composer track but got 0. " +
            "Check composerQuery and ComposerMap coverage."
        )
        XCTAssertTrue(
            tracks.allSatisfy { $0.license != .rejected },
            "All tracks should have a valid license"
        )
    }

    func testBaroqueTagChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel(id: "baroque", name: "Baroque", category: "Classical", icon: "music.quarternote.3", tags: ["baroque"], preferredSource: "internet_archive")
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(tags: channel.tags)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Baroque tag: \(tracks.count) tracks passed filtering")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title)")
        }
        XCTAssertFalse(
            tracks.isEmpty,
            "Expected ≥1 baroque tag track but got 0. " +
            "Check confidenceThreshold for tag-based channels."
        )
    }

    // Tests Chopin because IA's musopen collection has only 34 items and Bach/Vivaldi/Rachmaninoff
    // are not among them. Chopin is present as musopen-chopin with 208 audio files.
    func testMusopenChopinReturnsAtLeastOneTrack() async throws {
        let tracks: [Track]
        do {
            tracks = try await service.fetchMusopenTracks(composer: "chopin")
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Musopen Chopin: \(tracks.count) tracks")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title)")
        }
        XCTAssertFalse(
            tracks.isEmpty,
            "Expected ≥1 Musopen Chopin track but got 0. " +
            "Check fetchMusopenTracks title/subject query and IA musopen collection."
        )
        XCTAssertTrue(
            tracks.allSatisfy { $0.license != .rejected },
            "All Musopen tracks should have a valid license"
        )
    }

    func testResolveAudioURLReturnsPlayableFileURL() async throws {
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(
                composers: ["bach"],
                instruments: ["strings"]
            )
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard let first = tracks.first else {
            throw XCTSkip("No tracks returned by search — cannot test URL resolution")
        }
        let url: URL
        do {
            url = try await service.resolveAudioURL(for: first.id)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable during URL resolution: \(e.localizedDescription)")
        }
        print("Resolved audio URL: \(url.absoluteString)")
        XCTAssertTrue(
            url.absoluteString.contains("archive.org/download/"),
            "URL should be an IA download URL"
        )
        let ext = url.pathExtension.lowercased()
        XCTAssertTrue(
            ["mp3", "ogg", "flac", "m4a"].contains(ext),
            "Expected an audio file extension, got: \(ext)"
        )
    }

    // Parametrized over EVERY pure-Lucene registry channel — Curated music
    // AND the 21 LibriVox audiobook channels (auto-covers anything added to
    // ia_queries.json). Guards the end-to-end contract:
    //  (a) the query returns a healthy pool (not starved/empty)
    //  (b) every track is stamped with the channel's matchTag
    //  (c) every track passes Channel.matches — shared-DB queue not starved
    //  (d) the stamp is unique per channel (no cross-channel contamination)
    func testEveryRegistryChannelReturnsHealthyStampedPool() async throws {
        let registry = Channel.defaults.filter { $0.iaQueryEntry != nil }
        XCTAssertGreaterThanOrEqual(registry.count, 28,
            "expected the curated + LibriVox registry channels")

        for channel in registry {
            guard let entry = channel.iaQueryEntry else {
                XCTFail("Curated channel '\(channel.id)' has no ia_queries.json entry")
                continue
            }
            XCTAssertEqual(entry.matchTags, [channel.id],
                "\(channel.id): matchTags must be the per-channel stamp [\(channel.id)]")

            let tracks: [Track]
            do {
                tracks = try await service.fetchTracks(
                    iaQuery: entry.iaQuery, matchTags: entry.matchTags
                )
            } catch let e as URLError {
                throw XCTSkip("Network unavailable for \(channel.id): \(e.localizedDescription)")
            }
            print("\(channel.id): \(tracks.count) tracks")
            for t in tracks.prefix(3) { print("  \(t.title) — \(t.artist)") }

            XCTAssertGreaterThan(tracks.count, 20,
                "\(channel.id): query must return a healthy pool; got \(tracks.count)")
            XCTAssertTrue(tracks.allSatisfy { $0.tags.contains(Channel.stampToken(channel.id)) },
                "\(channel.id): every track must carry its namespaced stamp")
            XCTAssertTrue(tracks.allSatisfy { channel.matches($0) },
                "\(channel.id): stamped tracks must pass Channel.matches (queue not starved)")
            // No OTHER registry channel must claim these tracks (isolation).
            for other in registry where other.id != channel.id {
                XCTAssertFalse(tracks.contains { other.matches($0) },
                    "\(channel.id) tracks leaked into \(other.id) — stamp isolation broken")
            }
        }
    }
}

// MARK: - Spoken-word (LibriVox) integration tests

final class SpokenWordIntegrationTests: XCTestCase {

    private let service = InternetArchiveService()

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 60
    }

    func testGreekPhilosophyChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel(id: "greek-philosophy", name: "Greek Philosophy", category: "Audiobooks", icon: "building.columns", tags: ["plato"], contentType: .spokenWord, spokenWordCollections: ["librivoxaudio"], preferredSource: "internet_archive")
        let tracks: [Track]
        do {
            tracks = try await service.fetchSpokenWordTracks(channel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Greek Philosophy: \(tracks.count) tracks")
        for t in tracks.prefix(3) { print("  \(t.title) | \(t.license)") }
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 LibriVox philosophy track but got 0.")
        XCTAssertTrue(tracks.allSatisfy { $0.license != .rejected }, "All tracks must have valid license")
    }

    func testPoetryChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel(id: "lv-poetry", name: "Poetry", category: "Audiobooks", icon: "text.quote", tags: ["poetry"], contentType: .spokenWord, spokenWordCollections: ["librivoxaudio"], preferredSource: "internet_archive")
        let tracks: [Track]
        do {
            tracks = try await service.fetchSpokenWordTracks(channel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Poetry: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 LibriVox poetry track but got 0.")
    }

    func testScienceFictionGenreChannelReturnsAtLeastOneTrack() async throws {
        let channel = Channel(id: "lv-science-fiction", name: "Science Fiction", category: "Audiobooks", icon: "sparkles", tags: ["science fiction"], contentType: .spokenWord, spokenWordCollections: ["librivoxaudio"], preferredSource: "internet_archive")
        let tracks: [Track]
        do {
            tracks = try await service.fetchSpokenWordTracks(channel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Science Fiction (genre): \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 LibriVox sci-fi track but got 0.")
    }

    func testSpokenWordTracksHaveChannelTagsForMatching() async throws {
        let channel = Channel(id: "greek-philosophy", name: "Greek Philosophy", category: "Audiobooks", icon: "building.columns", tags: ["plato"], contentType: .spokenWord, spokenWordCollections: ["librivoxaudio"], preferredSource: "internet_archive")
        let tracks: [Track]
        do {
            tracks = try await service.fetchSpokenWordTracks(channel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard let first = tracks.first else {
            throw XCTSkip("No tracks returned — cannot verify tag matching")
        }
        XCTAssertTrue(
            channel.matches(first),
            "Fetched track must pass Channel.matches() — tags: \(first.tags)"
        )
    }
}

// MARK: - Search integration tests

final class SearchIntegrationTests: XCTestCase {

    private let service = InternetArchiveService()

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 60
    }

    func testSearchBeethovenReturnsResults() async throws {
        let groups: [SearchViewModel.ResultGroup]
        do {
            groups = try await service.search(query: "beethoven", page: 0)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("Search 'beethoven': \(groups.count) groups")
        for g in groups.prefix(3) { print("  \(g.id) — \(g.title)") }
        XCTAssertFalse(groups.isEmpty, "Expected ≥1 result for 'beethoven' on Internet Archive")
        XCTAssertTrue(groups.allSatisfy { !$0.id.isEmpty }, "All groups must have a non-empty identifier")
    }

    // Item 2: live search results must expose the IA collection so the row
    // can show it (e.g. "librivoxaudio"). Virtually every public IA audio
    // item belongs to at least one collection, so ≥1 must be non-nil.
    func testSearchResultsCarryCollection() async throws {
        let groups: [SearchViewModel.ResultGroup]
        do {
            groups = try await service.search(query: "beethoven", page: 0)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard !groups.isEmpty else {
            throw XCTSkip("No search results — cannot verify collection parsing")
        }
        let withCollection = groups.filter {
            !($0.collection ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        for g in withCollection.prefix(3) { print("  \(g.id) — collection: \(g.collection!)") }
        XCTAssertFalse(withCollection.isEmpty,
            "Expected ≥1 'beethoven' result to expose an IA collection")
    }

    func testFetchTracksForIdentifierReturnsPlayableFiles() async throws {
        let groups: [SearchViewModel.ResultGroup]
        do {
            groups = try await service.search(query: "beethoven symphony", page: 0)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard let first = groups.first else {
            throw XCTSkip("No search results — cannot test fetchTracksForIdentifier")
        }
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracksForIdentifier(first.id)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable fetching identifier \(first.id): \(e.localizedDescription)")
        }
        print("Tracks for '\(first.id)': \(tracks.count)")
        for t in tracks.prefix(3) { print("  \(t.title) — \(t.streamURL.lastPathComponent)") }
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 audio file for identifier \(first.id)")
        XCTAssertTrue(
            tracks.allSatisfy { t in
                let ext = (t.streamURL.lastPathComponent as NSString).pathExtension.lowercased()
                return ["mp3", "ogg", "flac", "m4a", "aac", "opus", "wav"].contains(ext)
            },
            "All tracks must have audio file URLs"
        )
    }
}

// MARK: - Whole book/album probe integration test

// Exercises the real multi-file probe end-to-end: PlayerViewModel.playEntireItem
// → resolveItemParts → live archive.org metadata → DB persistence. Uses the
// stable public-domain LibriVox item "art_of_war_librivox" (14 MP3 chapters).
@MainActor
final class WholeBookIntegrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 120
    }

    func testPlayEntireBookProbesNetworkAndPersistsParts() async throws {
        let db: DatabaseService
        do { db = try DatabaseService(path: ":memory:") }
        catch { throw XCTSkip("Could not open in-memory DB: \(error)") }

        let vm = PlayerViewModel(
            db: db,
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: db),
            audioPlayer: AudioPlayerService(),
            downloadManager: DownloadManager(db: db)
        )

        let identifier = "art_of_war_librivox"
        // Sanity-probe the network first so a transient IA outage skips
        // (rather than fails) the test.
        do {
            let probe = try await InternetArchiveService()
                .fetchTracksForIdentifier(identifier)
            guard probe.count >= 2 else {
                throw XCTSkip("\(identifier) is no longer multi-file (\(probe.count) files)")
            }
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }

        let itemTrack = Track(
            id: identifier, source: "internet_archive",
            title: "The Art of War", artist: "Sun Tzu", duration: 0,
            streamURL: URL(string: "https://archive.org/download/\(identifier)")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1.0, rawCreator: "Sun Tzu", composer: nil,
            instruments: [], metadataConfidence: 0.0)
        vm.currentChannel = Channel(
            id: "lv-history", name: "History", category: "Audiobooks",
            icon: "book", tags: ["history"], contentType: .spokenWord,
            preferredSource: "internet_archive")

        await vm.playEntireItem(from: itemTrack)

        XCTAssertNotNil(vm.overrideQueueTitle,
            "playEntireItem must set the screen-panel indicator after the probe")

        let persisted = await db.fetchTracks(forParentIdentifier: identifier)
        print("Persisted \(persisted.count) parts for \(identifier)")
        XCTAssertGreaterThanOrEqual(persisted.count, 2,
            "the probe must persist every chapter under parent_identifier")
        XCTAssertEqual(persisted.map(\.partNumber),
                       persisted.map(\.partNumber).sorted { ($0 ?? 0) < ($1 ?? 0) },
            "persisted parts must be ordered by part number")
    }
}

// MARK: - FMA scraper integration tests

final class FMAIntegrationTests: XCTestCase {

    private let service = FMAService()

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 60
    }

    func testClassicalChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-classical" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Classical: \(tracks.count) tracks")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title) | \(t.streamURL.absoluteString)")
        }
        XCTAssertFalse(
            tracks.isEmpty,
            "Expected ≥1 FMA Classical public-domain track but got 0."
        )
        XCTAssertTrue(
            tracks.allSatisfy { $0.source == "fma" },
            "All tracks should have source 'fma'"
        )
    }

    func testJazzChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-jazz" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Jazz: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA Jazz track but got 0.")
    }

    func testRockChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-rock" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Rock: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA Rock track but got 0.")
    }

    func testSoulRnbChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-soul-rnb" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Soul & R&B: \(tracks.count) tracks")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title) | \(t.license)")
        }
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA Soul-RB public-domain track but got 0.")
    }

    func testOldTimeChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-old-time" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Old-Time & Historic: \(tracks.count) tracks")
        for t in tracks.prefix(3) {
            print("  [\(t.composer ?? "nil")] \(t.title) | \(t.license)")
        }
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA Old-Time public-domain track but got 0.")
    }

    // UC7/UC10: FMA genre channels all return tracks.
    func testFMAInternationalChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-international" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA International: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA International track but got 0.")
    }

    func testFMAHipHopChannelReturnsAtLeastOnePDTrack() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-hip-hop" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        print("FMA Hip-Hop: \(tracks.count) tracks")
        XCTAssertFalse(tracks.isEmpty, "Expected ≥1 FMA Hip-Hop track but got 0.")
    }

    func testStreamURLRedirectsToMp3() async throws {
        let channel = Channel.defaults.first { $0.id == "fma-classical" }!
        let tracks: [Track]
        do {
            tracks = try await service.fetchTracks(forChannel: channel)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable: \(e.localizedDescription)")
        }
        guard let first = tracks.first else {
            throw XCTSkip("No FMA tracks returned — cannot test stream URL")
        }
        // Follow the redirect to verify it lands on a real MP3.
        var request = URLRequest(url: first.streamURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch let e as URLError {
            throw XCTSkip("Network unavailable following stream URL: \(e.localizedDescription)")
        }
        let finalURL = (response as? HTTPURLResponse)?.url ?? response.url!
        print("FMA stream resolved to: \(finalURL.absoluteString)")
        XCTAssertTrue(
            finalURL.absoluteString.contains("freemusicarchive.org") ||
            finalURL.absoluteString.contains("files.freemusicarchive.org"),
            "Expected stream URL to resolve within FMA CDN, got: \(finalURL)"
        )
    }
}
