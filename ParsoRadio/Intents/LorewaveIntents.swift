import AppIntents

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case channelNotFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .channelNotFound(let name):
            return "Could not find \"\(name)\""
        }
    }
}

struct PlayLorewaveIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Lorewave"
    static let description = IntentDescription("Resume your last listening session in Lorewave.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppIntentBridge.shared.resumePlayback()
        return .result()
    }
}

struct PlayChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Channel"
    static let description = IntentDescription("Start playing a specific channel on Lorewave.")
    static let openAppWhenRun = true
    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$channel) on Lorewave")
    }

    @Parameter(title: "Channel")
    var channel: ChannelEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let ch = Channel.defaults.first(where: { $0.id == channel.id }) else {
            throw IntentError.channelNotFound(channel.displayName)
        }
        await AppIntentBridge.shared.loadChannel(ch)
        return .result()
    }
}

struct PlayPodcastIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Podcast"
    static let description = IntentDescription("Start playing a podcast or news show on Lorewave.")
    static let openAppWhenRun = true
    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$podcast) on Lorewave")
    }

    @Parameter(title: "Podcast")
    var podcast: PodcastEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let ch = Channel.defaults.first(where: { $0.id == podcast.id }) else {
            throw IntentError.channelNotFound(podcast.displayName)
        }
        await AppIntentBridge.shared.loadChannel(ch)
        return .result()
    }
}
