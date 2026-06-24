import XCTest

final class RegressionContractSourceTests: XCTestCase {

    private var projectRoot: URL {
        let filePath = URL(fileURLWithPath: #file)
        var url = filePath
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.appendingPathComponent("Views/Player/NowPlayingSheet.swift").path) {
            url = filePath
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return url
    }

    func testNowPlayingSheetDoesNotHardcodeMusicFallback() throws {
        let path = projectRoot.appendingPathComponent("Views/Player/NowPlayingSheet.swift").path
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let dangerousPattern = "currentChannel?.mediaKind ?? .music"
        for (idx, line) in lines.enumerated() {
            if line.contains(dangerousPattern) {
                XCTFail("NowPlayingSheet.swift line \(idx + 1) contains banned pattern '\(dangerousPattern)'. Use activeMediaKind instead.")
            }
        }
    }

    func testMadeForYouSectionDoesNotGateOnHiddenState() throws {
        let path = projectRoot.appendingPathComponent("Views/Listen/MadeForYouSection.swift").path
        let content = try String(contentsOfFile: path, encoding: .utf8)
        if content.contains("if showSection") {
            XCTFail("MadeForYouSection.swift must not gate root body on hidden state 'if showSection'. Mount the section unconditionally.")
        }
    }

    func testInternetArchiveAudioSelectionIsMP3Only() throws {
        let path = projectRoot.appendingPathComponent("Core/Services/API/InternetArchiveService.swift").path
        let content = try String(contentsOfFile: path, encoding: .utf8)

        let bannedFormats = ["Ogg Vorbis", "Ogg", "FLAC", "Flac", "M4A", "m4a", "AAC", "aac", "Opus", "opus", "WAV", "wav", "SHN", "shn"]
        let lines = content.components(separatedBy: .newlines)

        var foundBanned: [(Int, String)] = []
        for (idx, line) in lines.enumerated() {
            for format in bannedFormats {
                if line.contains("\"\(format)\"") {
                    foundBanned.append((idx + 1, format))
                }
            }
        }

        if !foundBanned.isEmpty {
            let details = foundBanned.map { "  line \($0.0): contains '\($0.1)'" }.joined(separator: "\n")
            XCTFail("InternetArchiveService.swift must not accept non-MP3 formats in audio selectors:\n\(details)")
        }
    }

    func testLiveMusicServiceDoesNotFallbackToPoolFirst() throws {
        let path = projectRoot.appendingPathComponent("Core/Services/API/LiveMusicOnThisDayService.swift").path
        let content = try String(contentsOfFile: path, encoding: .utf8)
        if content.contains("pool.first") {
            XCTFail("LiveMusicOnThisDayService.swift must not fall back to 'pool.first' after validation failures. Show empty/error state instead.")
        }
    }

    func testAGENTSContainsRegressionContract() throws {
        let agentsURL = projectRoot.deletingLastPathComponent().appendingPathComponent("AGENTS.md")
        let content = try String(contentsOfFile: agentsURL.path, encoding: .utf8)
        XCTAssertTrue(content.contains("Regression Contract"), "AGENTS.md must contain 'Regression Contract' section")
    }

    func testBundledLoopURLDoesNotAcceptWAV() throws {
        let path = projectRoot.appendingPathComponent("Core/Services/API/AmbientStaticService.swift").path
        let content = try String(contentsOfFile: path, encoding: .utf8)
        if content.contains("\"wav\"") {
            XCTFail("AmbientStaticService.bundledLoopURL must not accept .wav. Only MP3 should be bundled for active playback.")
        }
    }
}
