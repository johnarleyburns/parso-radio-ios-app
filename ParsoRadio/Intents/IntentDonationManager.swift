import AppIntents

@MainActor
enum LorewaveIntentDonations {

    static func donateChannel(_ channel: Channel) {
        let intent = PlayChannelIntent()
        intent.channel = ChannelEntity(id: channel.id, displayName: channel.name,
                                        searchAliases: aliasesFor(channel))
        // AppIntents are donated automatically by the system when invoked via
        // Siri or Shortcuts. The explicit call here ensures the donation fires
        // for proactive suggestions even when the user manually switches channels.
        Task { @MainActor in
            try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    static func donatePodcast(_ channel: Channel) {
        let intent = PlayPodcastIntent()
        intent.podcast = PodcastEntity(id: channel.id, displayName: channel.name,
                                        searchAliases: aliasesFor(channel))
        Task { @MainActor in
            try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    private static func aliasesFor(_ channel: Channel) -> [String] {
        var aliases: [String] = []
        let base = channel.name
        if let parenIdx = base.firstIndex(of: "(") {
            let stripped = base[..<parenIdx].trimmingCharacters(in: .whitespaces)
            if stripped != base { aliases.append(stripped) }
        }
        return aliases
    }

    static func donateResume() {
        let intent = PlayLorewaveIntent()
        Task { @MainActor in
            try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }
}
