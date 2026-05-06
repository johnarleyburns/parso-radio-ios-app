import Foundation

@MainActor
final class ChannelListViewModel: ObservableObject {
    @Published var channels: [Channel] = Channel.defaults
    @Published var selectedChannel: Channel?

    func selectChannel(_ channel: Channel) {
        selectedChannel = channel
    }
}
