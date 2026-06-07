import Intents

private let appGroupSuite = "group.guru.parso.ios-radio-app"

private var appGroupDefaults: UserDefaults {
    UserDefaults(suiteName: appGroupSuite) ?? .standard
}

class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any { self }
}

extension IntentHandler: INPlayMediaIntentHandling {
    func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
        let lastId = appGroupDefaults.string(forKey: "lastChannelId") ?? "guitar-classical"
        appGroupDefaults.set(lastId, forKey: "siri.pendingChannelId")
        appGroupDefaults.set(Date().timeIntervalSince1970, forKey: "siri.pendingTimestamp")
        return INPlayMediaIntentResponse(code: .continueInApp, userActivity: nil)
    }
}
