import Foundation

enum MediaKind: String, Codable, CaseIterable, Sendable {
    case music
    case audiobook
    case podcast
    case lecture
    case ambient
}

struct PlaybackBehavior: Equatable, Sendable {
    enum QueueStyle: Sendable { case shuffledPool, sequentialNewestFirst, sequentialInOrder, singleLoop }

    let queueStyle: QueueStyle
    let allowsShuffleToggle: Bool
    let showsScrubbableProgress: Bool
    let supportsChapters: Bool
    let supportsSpeedControl: Bool
    let supportsSleepTimer: Bool
    let persistsResumePosition: Bool
    let supportsBookSkip: Bool
    let supportsBookmarks: Bool
    let startsAtZeroAlways: Bool
    let supportsTransportNavigation: Bool
}

extension MediaKind {
    var behavior: PlaybackBehavior {
        switch self {
        case .music:
            return .init(queueStyle: .shuffledPool, allowsShuffleToggle: true,
                         showsScrubbableProgress: false, supportsChapters: false,
                         supportsSpeedControl: false, supportsSleepTimer: true,
                         persistsResumePosition: false, supportsBookSkip: false,
                         supportsBookmarks: false, startsAtZeroAlways: false,
                         supportsTransportNavigation: true)
        case .audiobook:
            return .init(queueStyle: .sequentialInOrder, allowsShuffleToggle: false,
                         showsScrubbableProgress: true, supportsChapters: true,
                         supportsSpeedControl: true, supportsSleepTimer: true,
                         persistsResumePosition: true, supportsBookSkip: true,
                         supportsBookmarks: true, startsAtZeroAlways: false,
                         supportsTransportNavigation: true)
        case .podcast:
            return .init(queueStyle: .sequentialNewestFirst, allowsShuffleToggle: false,
                         showsScrubbableProgress: true, supportsChapters: false,
                         supportsSpeedControl: true, supportsSleepTimer: true,
                         persistsResumePosition: true, supportsBookSkip: false,
                         supportsBookmarks: true, startsAtZeroAlways: true,
                         supportsTransportNavigation: true)
        case .lecture:
            return .init(queueStyle: .sequentialInOrder, allowsShuffleToggle: false,
                         showsScrubbableProgress: true, supportsChapters: true,
                         supportsSpeedControl: true, supportsSleepTimer: true,
                         persistsResumePosition: true, supportsBookSkip: true,
                         supportsBookmarks: true, startsAtZeroAlways: false,
                         supportsTransportNavigation: true)
        case .ambient:
            return .init(queueStyle: .singleLoop, allowsShuffleToggle: false,
                         showsScrubbableProgress: false, supportsChapters: false,
                         supportsSpeedControl: false, supportsSleepTimer: true,
                         persistsResumePosition: false, supportsBookSkip: false,
                         supportsBookmarks: false, startsAtZeroAlways: false,
                         supportsTransportNavigation: false)
        }
    }
}
