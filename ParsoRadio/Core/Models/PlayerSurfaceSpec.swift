import Foundation

struct PlayerSurfaceSpec {
    let mediaKind: MediaKind
    let includesScrubSlider: Bool
    let includesElapsedTime: Bool
    let includesRemainingTime: Bool
    let includesWorkTimeLeft: Bool
    let includesJogControls: Bool
    let includesSpeedControl: Bool
    let includesChapters: Bool
    let includesBookmarks: Bool
    let includesSleepTimer: Bool
    let requiresMP3Only: Bool

    static func spec(for kind: MediaKind) -> PlayerSurfaceSpec {
        switch kind {
        case .music:
            return PlayerSurfaceSpec(
                mediaKind: .music,
                includesScrubSlider: true,
                includesElapsedTime: true,
                includesRemainingTime: true,
                includesWorkTimeLeft: false,
                includesJogControls: false,
                includesSpeedControl: false,
                includesChapters: false,
                includesBookmarks: false,
                includesSleepTimer: false,
                requiresMP3Only: true
            )
        case .audiobook:
            return PlayerSurfaceSpec(
                mediaKind: .audiobook,
                includesScrubSlider: true,
                includesElapsedTime: true,
                includesRemainingTime: true,
                includesWorkTimeLeft: true,
                includesJogControls: true,
                includesSpeedControl: true,
                includesChapters: true,
                includesBookmarks: true,
                includesSleepTimer: true,
                requiresMP3Only: true
            )
        case .lecture:
            return PlayerSurfaceSpec(
                mediaKind: .lecture,
                includesScrubSlider: true,
                includesElapsedTime: true,
                includesRemainingTime: true,
                includesWorkTimeLeft: true,
                includesJogControls: true,
                includesSpeedControl: true,
                includesChapters: true,
                includesBookmarks: true,
                includesSleepTimer: false,
                requiresMP3Only: true
            )
        case .podcast:
            return PlayerSurfaceSpec(
                mediaKind: .podcast,
                includesScrubSlider: true,
                includesElapsedTime: true,
                includesRemainingTime: true,
                includesWorkTimeLeft: false,
                includesJogControls: true,
                includesSpeedControl: true,
                includesChapters: false,
                includesBookmarks: true,
                includesSleepTimer: false,
                requiresMP3Only: true
            )
        case .ambient:
            return PlayerSurfaceSpec(
                mediaKind: .ambient,
                includesScrubSlider: false,
                includesElapsedTime: false,
                includesRemainingTime: false,
                includesWorkTimeLeft: false,
                includesJogControls: false,
                includesSpeedControl: false,
                includesChapters: false,
                includesBookmarks: false,
                includesSleepTimer: false,
                requiresMP3Only: true
            )
        }
    }
}
