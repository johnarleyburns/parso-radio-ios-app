import XCTest
@testable import ParsoMusic

final class LiveMusicCandidateValidatorTests: XCTestCase {

    func testCandidateWithOneMP3AndValidMetadataIsAccepted() {
        let files: [LiveMusicCandidateFile] = [
            .init(name: "track01.mp3", format: "VBR MP3")
        ]
        let validator = LiveMusicCandidateValidator()
        let result = validator.validate(
            identifier: "test-001",
            expectedMMDD: "06-23",
            title: "Live at Fillmore",
            creator: "Test Band",
            date: "1970-06-23T00:00:00Z",
            venue: "The Fillmore",
            coverage: "San Francisco, CA",
            files: files
        )
        switch result {
        case .accepted(let entry, let tracks):
            XCTAssertEqual(entry.displayName, "Live at Fillmore")
            XCTAssertEqual(tracks.count, 1)
        case .rejected:
            XCTFail("Should accept valid candidate")
        }
    }

    func testCandidateWithMultipleMP3sIsAccepted() {
        let files: [LiveMusicCandidateFile] = [
            .init(name: "part01.mp3", format: "128Kbps MP3"),
            .init(name: "part02.mp3", format: "128Kbps MP3"),
            .init(name: "part03.mp3", format: "128Kbps MP3")
        ]
        let validator = LiveMusicCandidateValidator()
        let result = validator.validate(
            identifier: "test-001",
            expectedMMDD: "06-23",
            title: "Live Show",
            creator: "Test Band",
            date: "1970-06-23",
            files: files
        )
        switch result {
        case .accepted(_, let tracks):
            XCTAssertEqual(tracks.count, 3)
        case .rejected:
            XCTFail("Should accept with 3 MP3 tracks")
        }
    }

    func testSHNOnlyFilesAreRejected() {
        let files: [LiveMusicCandidateFile] = [
            .init(name: "track01.shn", format: "Shorten")
        ]
        let validator = LiveMusicCandidateValidator()
        let result = validator.validate(
            identifier: "test-001",
            expectedMMDD: "06-23",
            title: "Show",
            creator: "Band",
            date: "1970-06-23",
            files: files
        )
        switch result {
        case .accepted:
            XCTFail("SHN-only candidate must be rejected")
        case .rejected(let reason):
            XCTAssertTrue(reason.contains("MP3") || reason.contains("playable") || reason.contains("audio"),
                "Rejection reason should mention lack of playable MP3 files")
        }
    }

    func testFLACOnlyFilesAreRejected() {
        let files: [LiveMusicCandidateFile] = [
            .init(name: "track01.flac", format: "Flac")
        ]
        let validator = LiveMusicCandidateValidator()
        let result = validator.validate(
            identifier: "test-001",
            expectedMMDD: "06-23",
            title: "Show",
            creator: "Band",
            date: "1970-06-23",
            files: files
        )
        switch result {
        case .accepted: XCTFail("FLAC-only must be rejected")
        case .rejected: break
        }
    }

    func testOggOnlyFilesAreRejected() {
        let files: [LiveMusicCandidateFile] = [
            .init(name: "track01.ogg", format: "Ogg Vorbis")
        ]
        let validator = LiveMusicCandidateValidator()
        let result = validator.validate(
            identifier: "test-001",
            expectedMMDD: "06-23",
            title: "Show",
            creator: "Band",
            date: "1970-06-23",
            files: files
        )
        switch result {
        case .accepted: XCTFail("Ogg-only must be rejected")
        case .rejected: break
        }
    }

    func testM4AOnlyFilesAreRejected() {
        let files: [LiveMusicCandidateFile] = [
            .init(name: "track01.m4a", format: "M4A")
        ]
        let validator = LiveMusicCandidateValidator()
        let result = validator.validate(
            identifier: "test-001",
            expectedMMDD: "06-23",
            title: "Show",
            creator: "Band",
            date: "1970-06-23",
            files: files
        )
        switch result {
        case .accepted: XCTFail("M4A-only must be rejected")
        case .rejected: break
        }
    }

    func testNoAudioFilesIsRejected() {
        let validator = LiveMusicCandidateValidator()
        let result = validator.validate(
            identifier: "test-001",
            expectedMMDD: "06-23",
            title: "Show",
            creator: "Band",
            date: "1970-06-23",
            files: []
        )
        switch result {
        case .accepted: XCTFail("No audio files must be rejected")
        case .rejected: break
        }
    }

    func testDateMismatchIsRejected() {
        let files: [LiveMusicCandidateFile] = [
            .init(name: "track01.mp3", format: "VBR MP3")
        ]
        let validator = LiveMusicCandidateValidator()
        let result = validator.validate(
            identifier: "test-001",
            expectedMMDD: "06-23",
            title: "Show",
            creator: "Band",
            date: "1970-12-25",
            files: files
        )
        switch result {
        case .accepted: XCTFail("Date mismatch must be rejected")
        case .rejected(let reason):
            XCTAssertTrue(reason.contains("date") || reason.contains("day"),
                "Rejection reason should mention date mismatch")
        }
    }

    func testMissingTitleWithCreatorAndVenueSynthesizesDisplayName() {
        let files: [LiveMusicCandidateFile] = [
            .init(name: "track01.mp3", format: "VBR MP3")
        ]
        let validator = LiveMusicCandidateValidator()
        let result = validator.validate(
            identifier: "test-001",
            expectedMMDD: "06-23",
            title: nil,
            creator: "Test Band",
            date: "1970-06-23",
            venue: "The Fillmore",
            files: files
        )
        switch result {
        case .accepted(let entry, _):
            XCTAssertFalse(entry.displayName.isEmpty, "Synthesized display name should not be empty")
            XCTAssertTrue(entry.displayName.contains("Test Band"), "Display name should include creator")
        case .rejected:
            XCTFail("Should accept with synthesized display name")
        }
    }

    func testMissingTitleAndInsufficientDataIsRejected() {
        let files: [LiveMusicCandidateFile] = [
            .init(name: "track01.mp3", format: "VBR MP3")
        ]
        let validator = LiveMusicCandidateValidator()
        let result = validator.validate(
            identifier: "test-001",
            expectedMMDD: "06-23",
            title: nil,
            creator: nil,
            date: "1970-06-23",
            files: files
        )
        switch result {
        case .accepted: XCTFail("Missing title and creator must be rejected")
        case .rejected: break
        }
    }
}
