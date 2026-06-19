import XCTest
@testable import ParsoMusic

@MainActor
final class KidsModeControllerTests: XCTestCase {
    // Each controller gets its own ephemeral defaults so tests never touch the
    // shared store or leave the app stuck in Kids Mode.
    private func makeController() -> KidsModeController {
        let suite = "KidsModeTests-\(UUID().uuidString)"
        return KidsModeController(defaults: UserDefaults(suiteName: suite)!)
    }

    func test_enableSetsFlagAndPin() {
        let c = makeController()
        XCTAssertFalse(c.isEnabled)
        c.enable(pin: "1234")
        XCTAssertTrue(c.isEnabled)
        XCTAssertTrue(c.verify(pin: "1234"))
        XCTAssertFalse(c.verify(pin: "9999"))
    }

    func test_disableRequiresCorrectPin() {
        let c = makeController()
        c.enable(pin: "1234")
        XCTAssertFalse(c.disable(pin: "0000"), "wrong PIN must not disable")
        XCTAssertTrue(c.isEnabled)
        XCTAssertTrue(c.disable(pin: "1234"))
        XCTAssertFalse(c.isEnabled)
    }

    func test_enableRejectsShortPin() {
        let c = makeController()
        c.enable(pin: "12")
        XCTAssertFalse(c.isEnabled, "a non-4-digit PIN must not enable Kids Mode")
    }

    func test_allowedChannelsAreExactlyTheTwoChildrensChannels() {
        let ids = Set(KidsModeController.allowedChannels().map(\.id))
        XCTAssertEqual(ids, ["ambient-yellowstone", "ambient-flowing-water", "ambient-rain", "ambient-ocean"],
            "Kids Mode must expose exactly the four ambient channels (and they must exist)")
    }

    func test_normalizeKeepsDigitsAndCapsAtFour() {
        XCTAssertEqual(KidsModeController.normalize("12ab345"), "1234")
        XCTAssertEqual(KidsModeController.normalize("9"), "9")
    }

    // Enabling Kids Mode must immediately drop the user onto a children's
    // channel if they aren't on one — so back-track can't expose non-kid
    // content. shouldRedirect is the testable predicate driving that.
    func test_shouldRedirect_whenNotOnAllowedChannel() {
        XCTAssertTrue(KidsModeController.shouldRedirect(fromChannelId: nil),
            "no current channel → must redirect into kids content")
        XCTAssertTrue(KidsModeController.shouldRedirect(fromChannelId: "oxford-philosophy"),
            "non-kids channel → must redirect")
        XCTAssertTrue(KidsModeController.shouldRedirect(fromChannelId: "news-bbc"),
            "news channel → must redirect")
    }

    func test_shouldRedirect_whenAlreadyOnKidsChannel() {
        XCTAssertFalse(KidsModeController.shouldRedirect(fromChannelId: "ambient-yellowstone"))
        XCTAssertFalse(KidsModeController.shouldRedirect(fromChannelId: "ambient-ocean"))
    }

    // needsRedirect — the unified decision that considers BOTH the channel
    // allow-list AND the per-playlist isKidSafe flag.

    func test_needsRedirect_kidSafePlaylistWins_evenOnNonKidsChannel() {
        // If we're inside a kid-safe playlist, the playlist context wins; the
        // channel allow-list doesn't matter (the playlist drives playback).
        XCTAssertFalse(KidsModeController.needsRedirect(
            currentChannelId: "news-bbc",
            currentPlaylistIsKidSafe: true))
    }

    func test_needsRedirect_nonKidSafePlaylist_alwaysRedirects() {
        XCTAssertTrue(KidsModeController.needsRedirect(
            currentChannelId: "ambient-yellowstone",
            currentPlaylistIsKidSafe: false),
            "a non-kid-safe playlist must redirect even if the channel was kid-safe")
    }

    func test_needsRedirect_noPlaylist_fallsBackToChannelAllowList() {
        XCTAssertFalse(KidsModeController.needsRedirect(
            currentChannelId: "ambient-yellowstone",
            currentPlaylistIsKidSafe: nil))
        XCTAssertTrue(KidsModeController.needsRedirect(
            currentChannelId: "oxford-philosophy",
            currentPlaylistIsKidSafe: nil))
        XCTAssertTrue(KidsModeController.needsRedirect(
            currentChannelId: nil,
            currentPlaylistIsKidSafe: nil),
            "no context at all → redirect")
    }

    // invariantHolds — the runtime guarantee Kids Mode must always satisfy.

    func test_invariantHolds_kidSafePlaylist_holdsRegardlessOfChannel() {
        XCTAssertTrue(KidsModeController.invariantHolds(
            currentChannelId: nil, currentPlaylistIsKidSafe: true))
        XCTAssertTrue(KidsModeController.invariantHolds(
            currentChannelId: "news-bbc", currentPlaylistIsKidSafe: true))
    }

    func test_invariantHolds_nonKidSafePlaylist_alwaysFails() {
        XCTAssertFalse(KidsModeController.invariantHolds(
            currentChannelId: "ambient-yellowstone", currentPlaylistIsKidSafe: false),
            "a non-kid-safe playlist context violates the invariant even on a kids channel")
    }

    func test_invariantHolds_noPlaylist_requiresAllowedChannel() {
        XCTAssertTrue(KidsModeController.invariantHolds(
            currentChannelId: "ambient-yellowstone", currentPlaylistIsKidSafe: nil))
        XCTAssertFalse(KidsModeController.invariantHolds(
            currentChannelId: "oxford-philosophy", currentPlaylistIsKidSafe: nil))
        XCTAssertFalse(KidsModeController.invariantHolds(
            currentChannelId: nil, currentPlaylistIsKidSafe: nil),
            "no channel and no playlist → invariant fails (must load a kids channel)")
    }
}
