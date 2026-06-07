import Foundation

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
        await vm.restoreLastSession(fallbackChannel: channel, autoPlay: true)
    }

    func loadChannel(_ channel: Channel) async {
        guard !KidsModeController.shared.isEnabled,
              let vm = playerVM else { return }
        await vm.load(channel: channel, autoPlay: true)
    }
}
