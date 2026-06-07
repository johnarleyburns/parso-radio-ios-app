import SwiftUI

struct ChannelListScreen: View {
    let category: String
    let channels: [Channel]
    let onSelect: (Channel) -> Void

    @StateObject private var podcastStore = PodcastSubscriptionStore.shared
    @State private var showAddPodcast = false

    private var isPodcastsCategory: Bool { category == "Podcasts" }

    private var allChannels: [Channel] {
        if isPodcastsCategory {
            let subs = podcastStore.subscriptions.map { podcastStore.channel(from: $0) }
            return channels + subs
        }
        return channels
    }

    var body: some View {
        List {
            ForEach(allChannels) { channel in
                let isSubscribed = channel.id.hasPrefix("podcast-")
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

                    if !isSubscribed {
                        NavigationLink(value: MenuRoute.channelInfo(channel)) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel("\(channel.name) info")
                    }
                }
                .swipeActions(edge: .trailing) {
                    if isSubscribed {
                        Button(role: .destructive) {
                            if let sub = podcastStore.subscriptions.first(where: {
                                "podcast-\($0.id)" == channel.id
                            }) {
                                Task { await podcastStore.remove(sub) }
                            }
                        } label: {
                            Label("Unsubscribe", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPodcastsCategory {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddPodcast = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                    }
                    .accessibilityLabel("Add podcast feed")
                }
            }
        }
        .sheet(isPresented: $showAddPodcast) {
            PodcastAddView()
        }
    }
}
