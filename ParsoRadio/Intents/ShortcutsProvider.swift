import AppIntents

struct LorewaveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayLorewaveIntent(),
            phrases: [
                "Play \(.applicationName)",
                "Resume \(.applicationName)",
                "Start \(.applicationName)"
            ],
            shortTitle: "Play Lorewave",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: PlayChannelIntent(),
            phrases: [
                "Play \(\.$channel) on \(.applicationName)",
                "Start \(\.$channel) on \(.applicationName)"
            ],
            shortTitle: "Play Channel",
            systemImageName: "music.note"
        )

        AppShortcut(
            intent: PlayPodcastIntent(),
            phrases: [
                "Play the news on \(.applicationName)",
                "Play \(\.$podcast) on \(.applicationName)"
            ],
            shortTitle: "Play Podcast",
            systemImageName: "radio.fill"
        )
    }
}
