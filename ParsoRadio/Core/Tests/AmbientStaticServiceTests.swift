import XCTest
@testable import ParsoMusic

final class AmbientStaticServiceTests: XCTestCase {

    private let svc = AmbientStaticService()

    private func channel(_ id: String) -> Channel {
        Channel.defaults.first { $0.id == id }!
    }

    func testLoopSourcesAreTheUserSelectedCC0Sounds() {
        let cases: [(id: String, title: String, artist: String, sid: String, url: String)] = [
            ("ambient-flowing-water", "Flowing Water", "eardeer", "443869",
             "https://cdn.freesound.org/previews/443/443869_2155630-hq.mp3"),
            ("ambient-rain", "Rainy Day", "svampen", "334149",
             "https://cdn.freesound.org/previews/334/334149_5910095-hq.mp3"),
            ("ambient-ocean", "Ocean Waves", "Nox_Sound", "829629",
             "https://cdn.freesound.org/previews/829/829629_9250976-hq.mp3"),
        ]
        for c in cases {
            let tracks = svc.fetchTracks(channel: channel(c.id))
            XCTAssertEqual(tracks.count, 1, "\(c.id): exactly one looping track")
            let t = tracks[0]
            XCTAssertEqual(t.title, c.title)
            XCTAssertEqual(t.artist, c.artist)
            XCTAssertEqual(t.license, .cc0, "loop sources must be CC0")
            XCTAssertEqual(t.id, "freesound-\(c.sid)")
            XCTAssertEqual(t.streamURL.absoluteString, c.url,
                "\(c.id): streams the chosen sound's HQ preview as fallback")
        }
    }

    // No assets are bundled in the unit-test target, so the resolver must
    // return nil → the streaming fallback path is taken. (When real WAV/CAF
    // files are committed under Resources/Audio they are picked up instead.)
    func testBundledLoopURLNilWhenNoAssetBundled() {
        XCTAssertNil(AmbientStaticService.bundledLoopURL(forChannelId: "ambient-rain"))
        XCTAssertNil(AmbientStaticService.bundledLoopURL(forChannelId: ""))
    }

    func testAmbientLoopChannelsAreContentTypeLoop() {
        for id in ["ambient-flowing-water", "ambient-rain", "ambient-ocean"] {
            XCTAssertEqual(channel(id).contentType, .ambientLoop,
                "\(id) must be an ambient-loop channel (drives the info-only UI)")
        }
    }
}
