import AppIntents
import Foundation

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case channelNotFound(String)
    case kidsModeActive
    case appNotAvailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .channelNotFound(let name):
            return "Could not find \"\(name)\""
        case .kidsModeActive:
            return "Kids Mode is active — Siri playback is not available"
        case .appNotAvailable:
            return "Lorewave is not available right now"
        }
    }
}

struct PlayLorewaveIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Lorewave"
    static let description = IntentDescription("Resume your last listening session in Lorewave.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard !KidsModeController.shared.isEnabled else {
            throw IntentError.kidsModeActive
        }

        // In-process: the app is running (foreground or background), PlayerViewModel exists.
        if let vm = AppIntentBridge.shared.playerVM {
            let lastId = UserDefaults.standard.string(forKey: "lastChannelId") ?? "for-you"
            let channel = Channel.defaults.first { $0.id == lastId }
                ?? Channel.defaults.first { $0.id == "for-you" }
                ?? Channel.defaults[0]

            AppIntentBridge.shared.setPendingCommand(channelId: channel.id)
            NotificationCenter.default.post(name: .siriIntentDidPerform, object: nil)
            await vm.restoreLastSession(fallbackChannel: channel, autoPlay: false)
            LorewaveIntentDonations.donateResume()
            return .result()
        }

        // Extension process: store the pending command for the main app to pick up.
        AppIntentBridge.shared.storePendingCommandInAppGroup(
            channelId: UserDefaults.standard.string(forKey: "lastChannelId") ?? "for-you")
        return .result()
    }
}

struct PlayChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Channel"
    static let description = IntentDescription("Start playing a specific channel on Lorewave.")
    static let openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$channel) on Lorewave")
    }

    @Parameter(title: "Channel")
    var channel: ChannelEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard !KidsModeController.shared.isEnabled else {
            throw IntentError.kidsModeActive
        }
        guard let ch = Channel.defaults.first(where: { $0.id == channel.id }) else {
            throw IntentError.channelNotFound(channel.displayName)
        }

        // In-process: the app is running, PlayerViewModel exists.
        if let vm = AppIntentBridge.shared.playerVM {
            AppIntentBridge.shared.setPendingCommand(channelId: ch.id)
            NotificationCenter.default.post(name: .siriIntentDidPerform, object: nil)
            await vm.load(channel: ch, autoPlay: false)
            LorewaveIntentDonations.donateChannel(ch)
            if ch.category == "Podcasts" {
                LorewaveIntentDonations.donatePodcast(ch)
            }
            return .result()
        }

        // Extension process: store pending command for main app.
        AppIntentBridge.shared.storePendingCommandInAppGroup(channelId: ch.id)
        return .result()
    }
}

struct PlayPodcastIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Podcast"
    static let description = IntentDescription("Start playing a podcast or news show on Lorewave.")
    static let openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$podcast) on Lorewave")
    }

    @Parameter(title: "Podcast")
    var podcast: PodcastEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard !KidsModeController.shared.isEnabled else {
            throw IntentError.kidsModeActive
        }
        guard let ch = Channel.defaults.first(where: { $0.id == podcast.id }) else {
            throw IntentError.channelNotFound(podcast.displayName)
        }

        // In-process: the app is running, PlayerViewModel exists.
        if let vm = AppIntentBridge.shared.playerVM {
            AppIntentBridge.shared.setPendingCommand(channelId: ch.id)
            NotificationCenter.default.post(name: .siriIntentDidPerform, object: nil)
            await vm.load(channel: ch, autoPlay: false)
            LorewaveIntentDonations.donatePodcast(ch)
            return .result()
        }

        // Extension process: store pending command for main app.
        AppIntentBridge.shared.storePendingCommandInAppGroup(channelId: ch.id)
        return .result()
    }
}
