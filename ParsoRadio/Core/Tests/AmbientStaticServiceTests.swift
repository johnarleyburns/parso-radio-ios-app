import XCTest
@testable import ParsoMusic

final class AmbientStaticServiceTests: XCTestCase {

    private let svc = AmbientStaticService()

    private func channel(_ id: String) -> Channel {
        Channel.defaults.first { $0.id == id }!
    }

    func testLoopSourcesAndLicensesAreCorrect() {
        // All three ambient loop sources are CC0 (public domain).
        let cases: [(id: String, title: String, artist: String, sid: String,
                     license: LicenseType, url: String)] = [
            ("ambient-flowing-water", "Flowing Water", "eardeer", "443869", .cc0,
             "https://cdn.freesound.org/previews/443/443869_2155630-hq.mp3"),
            ("ambient-rain", "Rainy Day", "speakwithanimals", "525046", .cc0,
             "https://cdn.freesound.org/previews/525/525046_10637780-hq.mp3"),
            ("ambient-ocean", "Ocean Waves", "Nox_Sound", "829629", .cc0,
             "https://cdn.freesound.org/previews/829/829629_9250976-hq.mp3"),
        ]
        for c in cases {
            let tracks = svc.fetchTracks(channel: channel(c.id))
            XCTAssertEqual(tracks.count, 1, "\(c.id): exactly one looping track")
            let t = tracks[0]
            XCTAssertEqual(t.title, c.title)
            XCTAssertEqual(t.artist, c.artist)
            XCTAssertEqual(t.license, c.license,
                "\(c.id): license must match the Freesound source")
            XCTAssertEqual(t.id, "freesound-\(c.sid)")
            XCTAssertEqual(t.streamURL.absoluteString, c.url,
                "\(c.id): streams the chosen sound's HQ preview as fallback")
        }
    }

    // The seamless WAV loops are committed under Resources/Audio and bundled
    // into the app (the test host), so the resolver must return a local
    // file URL — that is the offline + gapless path. Unknown/empty → nil.
    func testBundledLoopURLResolvesCommittedWavAssets() {
        for id in ["ambient-flowing-water", "ambient-rain", "ambient-ocean"] {
            guard let url = AmbientStaticService.bundledLoopURL(forChannelId: id) else {
                XCTFail("\(id): a bundled loop asset must be found"); continue
            }
            XCTAssertTrue(url.isFileURL, "\(id): must resolve to a LOCAL file")
            XCTAssertEqual(url.deletingPathExtension().lastPathComponent, id)
            XCTAssertEqual(url.pathExtension.lowercased(), "wav")
        }
        XCTAssertNil(AmbientStaticService.bundledLoopURL(forChannelId: "nope-xyz"))
        XCTAssertNil(AmbientStaticService.bundledLoopURL(forChannelId: ""))
    }

    // The looping backdrop videos are committed and bundled into the app.
    func testBundledVideoURLResolvesCommittedClips() {
        for id in ["ambient-flowing-water", "ambient-rain", "ambient-ocean"] {
            guard let url = AmbientStaticService.bundledVideoURL(forChannelId: id) else {
                XCTFail("\(id): a bundled loop video must be found"); continue
            }
            XCTAssertTrue(url.isFileURL, "\(id): video must be a LOCAL file")
            XCTAssertEqual(url.deletingPathExtension().lastPathComponent, id)
            XCTAssertEqual(url.pathExtension.lowercased(), "mp4")
        }
        XCTAssertNil(AmbientStaticService.bundledVideoURL(forChannelId: "nope"))
        XCTAssertNil(AmbientStaticService.bundledVideoURL(forChannelId: ""))
    }

    func testAmbientLoopChannelsAreContentTypeLoop() {
        for id in ["ambient-flowing-water", "ambient-rain", "ambient-ocean"] {
            XCTAssertEqual(channel(id).contentType, .ambientLoop,
                "\(id) must be an ambient-loop channel (drives the info-only UI)")
        }
    }
}
