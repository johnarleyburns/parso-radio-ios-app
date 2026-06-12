import Foundation

enum AppGroup {
    static let suiteName = "group.guru.parso.ios-radio-app"
}

extension Notification.Name {
    static let siriIntentDidPerform = Notification.Name("SiriIntentDidPerform")
}

@MainActor
final class AppIntentBridge {
    static let shared = AppIntentBridge()
    weak var playerVM: PlayerViewModel?

    private init() {}

    func resumePlayback() async {
        guard !KidsModeController.shared.isEnabled,
              let vm = playerVM else { return }
        let lastId = UserDefaults.standard.string(forKey: "lastChannelId")
            ?? "guitar-classical"
        let channel = Channel.defaults.first { $0.id == lastId }
            ?? Channel.defaults.first { $0.id == "guitar-classical" }
            ?? Channel.defaults[0]

        setPendingCommand(channelId: channel.id)
        NotificationCenter.default.post(name: .siriIntentDidPerform, object: nil)
        await vm.restoreLastSession(fallbackChannel: channel, autoPlay: false)
        LorewaveIntentDonations.donateResume()
    }

    func loadChannel(_ channel: Channel) async {
        guard !KidsModeController.shared.isEnabled,
              let vm = playerVM else { return }

        setPendingCommand(channelId: channel.id)
        NotificationCenter.default.post(name: .siriIntentDidPerform, object: nil)
        await vm.load(channel: channel, autoPlay: false)

        LorewaveIntentDonations.donateChannel(channel)
        if channel.category == "Podcasts" {
            LorewaveIntentDonations.donatePodcast(channel)
        }
    }

    func setPendingCommand(channelId: String) {
        let defaults = UserDefaults.standard
        defaults.set(channelId, forKey: "siri.pendingChannelId")
        defaults.set(Date().timeIntervalSince1970, forKey: "siri.pendingTimestamp")
    }

    func storePendingCommandInAppGroup(channelId: String) {
        let defaults = UserDefaults.appGroup
        defaults.set(channelId, forKey: "siri.pendingChannelId")
        defaults.set(Date().timeIntervalSince1970, forKey: "siri.pendingTimestamp")
    }
}

extension UserDefaults {
    static var appGroup: UserDefaults {
        UserDefaults(suiteName: AppGroup.suiteName) ?? .standard
    }
}
