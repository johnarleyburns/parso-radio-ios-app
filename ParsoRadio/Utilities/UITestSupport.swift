import Foundation

/// Deterministic state seeding for XCUITest runs. Activated only by the
/// `-uiTestSeed` launch argument, which production builds never pass. All
/// database writes are compiled out of release builds.
enum UITestSupport {
    static var isActive: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTestSeed")
        #else
        false
        #endif
    }

    static let bookIdentifier = "gallipoli_ia"
    static let albumIdentifier = "album_ia"
    static let musicTrackId = "album_ia/track_01.mp3"

    /// First (lowest-bitrate) variant id for a chapter — the one `dedupeParts`
    /// keeps. UI tests reference these stable ids.
    static func survivingChapterId(_ n: Int) -> String {
        "\(bookIdentifier)/gallipoli_\(String(format: "%02d", n))_64kb.mp3"
    }

    @MainActor
    static func seed(db: DatabaseService) async {
        #if DEBUG
        // Suppress the onboarding taste-picker cover so the Listen view is
        // interactive (otherwise the onboarding fullScreenCover sits on top and
        // swallows every tap). ToS is bypassed via the content gate in the App.
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(false, forKey: "kidsMode.enabled")

        await db.wipeAllData()
        // wipeAllData() intentionally preserves the favorites table; clear the
        // ids these tests toggle so each run starts from a known (unfavorited)
        // state.
        await db.deleteFavorite(id: bookIdentifier)
        await db.deleteFavorite(id: albumIdentifier)

        // Seed the "Gallipoli" audiobook with the legacy triple-variant bug:
        // 5 chapters × 3 MP3 bitrates = 15 rows with sequential part numbers.
        var tracks: [Track] = []
        var pn = 0
        for n in 1...5 {
            for bitrate in ["64kb", "128kb", "vbr"] {
                pn += 1
                let id = "\(bookIdentifier)/gallipoli_\(String(format: "%02d", n))_\(bitrate).mp3"
                tracks.append(Track(
                    id: id, source: "internet_archive",
                    title: "Chapter \(n)", artist: "John Masefield",
                    duration: 300,
                    streamURL: URL(string: "https://archive.org/download/\(id)")!,
                    downloadURL: nil, localFilePath: nil,
                    license: .publicDomain, tags: [],
                    qualityScore: 0.7, rawCreator: "John Masefield", composer: nil,
                    instruments: [], metadataConfidence: 1.0,
                    partNumber: pn, totalParts: 15, parentIdentifier: bookIdentifier,
                    isMultiPart: true, collectionTitle: "Gallipoli"))
            }
        }

        // A clean 3-track music album so the detail sheet (with the favorite
        // button) is reachable offline via the player's "Album tracks" button.
        for n in 1...3 {
            let id = "\(albumIdentifier)/track_\(String(format: "%02d", n)).mp3"
            tracks.append(Track(
                id: id, source: "internet_archive",
                title: "Song \(n)", artist: "The Testers",
                duration: 200,
                streamURL: URL(string: "https://archive.org/download/\(id)")!,
                downloadURL: nil, localFilePath: nil,
                license: .publicDomain, tags: [],
                qualityScore: 0.7, rawCreator: "The Testers", composer: nil,
                instruments: [], metadataConfidence: 1.0,
                partNumber: n, totalParts: 3, parentIdentifier: albumIdentifier,
                isMultiPart: true, collectionTitle: "Test Album"))
        }

        await db.saveTracks(tracks)

        // Recently played: two chapters of the book (spoken) + one album track.
        await db.recordPlayed(channelId: "direct",
                              trackId: survivingChapterId(1), mediaKind: "audiobook")
        await db.recordPlayed(channelId: "direct",
                              trackId: survivingChapterId(2), mediaKind: "audiobook")
        await db.recordPlayed(channelId: "direct",
                              trackId: musicTrackId, mediaKind: "music")

        // Saved book position so resume seeks into chapter 2.
        await db.savePosition(
            channelId: PlayerViewModel.bookPositionKey(parentIdentifier: bookIdentifier),
            trackId: survivingChapterId(2), seconds: 123)
        #endif
    }
}
