import SwiftUI

/// Channels within one category, reached by drilling in from the Main Menu.
/// Tap a channel to play it (returns to the player); tap the ⓘ for channel
/// info (pushed onto the same nav stack).
struct ChannelListScreen: View {
    let category: String
    let channels: [Channel]
    let onSelect: (Channel) -> Void

    var body: some View {
        List {
            ForEach(channels) { channel in
                HStack(spacing: 8) {
                    Button {
                        onSelect(channel)
                    } label: {
                        HStack {
                            Label(channel.name, systemImage: channel.icon)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plays this channel")

                    NavigationLink(value: MenuRoute.channelInfo(channel)) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel("\(channel.name) info")
                }
            }
        }
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
    }
}
