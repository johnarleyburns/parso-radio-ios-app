import XCTest
@testable import ParsoMusic

final class AudioFormatPolicyTests: XCTestCase {

    func testSharedMP3SelectorExistsAndRejectsNonMP3() {
        let selector = MP3AudioFormatSelector()

        // MP3 variants must be accepted
        XCTAssertTrue(selector.isAcceptedFormat("VBR MP3"), "VBR MP3 must be accepted")
        XCTAssertTrue(selector.isAcceptedFormat("128Kbps MP3"), "128Kbps MP3 must be accepted")
        XCTAssertTrue(selector.isAcceptedFormat("64Kbps MP3"), "64Kbps MP3 must be accepted")
        XCTAssertTrue(selector.isAcceptedFormat("MP3"), "MP3 must be accepted")
        XCTAssertTrue(selector.isAcceptedFormat("128Kbps MP3"), "128Kbps MP3 must be accepted")
        XCTAssertTrue(selector.isAcceptedFormatByExtension("file.mp3"), ".mp3 must be accepted")

        // Non-MP3 formats must be rejected
        XCTAssertFalse(selector.isAcceptedFormat("Ogg Vorbis"), "Ogg Vorbis must be rejected")
        XCTAssertFalse(selector.isAcceptedFormat("VBR ZIP"), "VBR ZIP/Ogg must be rejected")
        XCTAssertFalse(selector.isAcceptedFormat("Flac"), "FLAC must be rejected")
        XCTAssertFalse(selector.isAcceptedFormat("24-bit Flac"), "24-bit FLAC must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file.ogg"), ".ogg must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file.flac"), ".flac must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file.m4a"), ".m4a must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file.aac"), ".aac must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file.opus"), ".opus must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file.wav"), ".wav must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file.shn"), ".shn must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file.mp4"), ".mp4 must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file.mov"), ".mov must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file.m4v"), ".m4v must be rejected")

        // Metadata-only or no extension
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file"), "no extension must be rejected")
        XCTAssertFalse(selector.isAcceptedFormatByExtension("file."), "dot-only must be rejected")

        // VBR MP3 by extension still accepted
        XCTAssertTrue(selector.isAcceptedFormatByExtension("track.mp3"), "track.mp3 must be accepted")
    }

    func testAllNonMP3FormatsAreRejected() {
        let selector = MP3AudioFormatSelector()
        let nonMP3Formats = [
            "Ogg Vorbis", "Vorbis", "FLAC", "Flac", "24-bit Flac",
            "M4A", "AAC", "Opus", "WAV", "Wave", "AIFF",
            "SHN", "Shorten", "MPEG-4", "QuickTime"
        ]
        for fmt in nonMP3Formats {
            XCTAssertFalse(selector.isAcceptedFormat(fmt), "Format '\(fmt)' must be rejected")
        }

        let nonMP3Extensions = ["ogg", "flac", "m4a", "aac", "opus", "wav", "shn", "aiff", "caf", "mp4", "mov", "m4v"]
        for ext in nonMP3Extensions {
            XCTAssertFalse(selector.isAcceptedFormatByExtension("file.\(ext)"), "Extension .\(ext) must be rejected")
        }
    }

    func testMP3VariantsAreAccepted() {
        let selector = MP3AudioFormatSelector()
        let mp3Formats = ["VBR MP3", "128Kbps MP3", "64Kbps MP3", "MP3", "256Kbps MP3", "320Kbps MP3", "192Kbps MP3"]
        for fmt in mp3Formats {
            XCTAssertTrue(selector.isAcceptedFormat(fmt), "Format '\(fmt)' must be accepted")
        }
    }
}
