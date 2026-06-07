import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var selectedChannel: Channel?
    @State private var showAddPodcast = false
    @StateObject private var podcastStore = PodcastSubscriptionStore.shared

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                channelList
                if playerVM.currentTrack != nil {
                    miniPlayer
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Lorewave")
            .navigationDestination(item: $selectedChannel) { channel in
                PlayerView(channel: channel)
            }
            .sheet(isPresented: $showAddPodcast) {
                PodcastAddView()
            }
        }
        .animation(.spring(duration: 0.3), value: playerVM.currentTrack != nil)
    }

    // MARK: - Channel list

    private var channelList: some View {
        ScrollView {
            VStack(spacing: 28) {
                ForEach(Channel.categories, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        categoryHeader(for: category)

                        VStack(spacing: 8) {
                            ForEach(Channel.defaults.filter { $0.category == category }) { channel in
                                channelRowView(for: channel)
                            }
                            if category == "Podcasts" {
                                ForEach(podcastStore.subscriptions) { sub in
                                    channelRowView(
                                        for: podcastStore.channel(from: sub),
                                        subtitle: sub.feedURL
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, playerVM.currentTrack != nil ? 80 : 16)
        }
    }

    @ViewBuilder
    private func categoryHeader(for category: String) -> some View {
        HStack {
            Text(category)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if category == "Podcasts" {
                Button {
                    showAddPodcast = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Add podcast feed")
            }
        }
        .padding(.horizontal, 20)
    }

    private func channelRowView(for channel: Channel, subtitle: String? = nil) -> some View {
        let isActive = playerVM.currentChannel?.id == channel.id
        return ChannelRow(
            channel: channel,
            subtitle: subtitle,
            isActive: isActive,
            isLoading: isActive && playerVM.isLoading
        ) {
            selectedChannel = channel
        }
    }

    // MARK: - Mini player

    private var miniPlayer: some View {
        Button {
            if let ch = playerVM.currentChannel { selectedChannel = ch }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ChannelCategoryStyle.gradient(for: playerVM.currentChannel?.category ?? ""))
                        .frame(width: 44, height: 44)
                    Image(systemName: playerVM.currentChannel?.icon ?? "music.note")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(playerVM.currentTrack?.title ?? "")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(playerVM.currentTrack?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if playerVM.isLoading {
                    ProgressView()
                        .frame(width: 44, height: 44)
                } else {
                    Button {
                        playerVM.togglePlayPause()
                    } label: {
                        Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Channel row

private struct ChannelRow: View {
    let channel: Channel
    var subtitle: String?
    let isActive: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ChannelCategoryStyle.gradient(for: channel.category))
                        .frame(width: 44, height: 44)
                    Image(systemName: channel.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(.primary)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isActive {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .symbolEffect(.variableColor.iterative)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ChannelListView()
        .environmentObject(PlayerViewModel(
            db: try! DatabaseService(path: ":memory:"),
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: try! DatabaseService(path: ":memory:")),
            audioPlayer: AudioPlayerService(),
            downloadManager: DownloadManager(db: try! DatabaseService(path: ":memory:"))
        ))
}
