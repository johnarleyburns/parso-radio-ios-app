import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var selectedChannel: Channel?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                channelList
                if playerVM.currentTrack != nil {
                    miniPlayer
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Parso Radio")
            .navigationDestination(item: $selectedChannel) { channel in
                PlayerView(channel: channel)
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
                        Text(category)
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 20)

                        VStack(spacing: 8) {
                            ForEach(Channel.defaults.filter { $0.category == category }) { channel in
                                let isActive = playerVM.currentChannel?.id == channel.id
                                ChannelRow(
                                    channel: channel,
                                    isActive: isActive,
                                    isLoading: isActive && playerVM.isLoading
                                ) {
                                    selectedChannel = channel
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

    // MARK: - Mini player

    private var miniPlayer: some View {
        Button {
            if let ch = playerVM.currentChannel { selectedChannel = ch }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(categoryGradient(for: playerVM.currentChannel?.category ?? ""))
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
    let isActive: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(categoryGradient(for: channel.category))
                        .frame(width: 44, height: 44)
                    Image(systemName: channel.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }

                Text(channel.name)
                    .font(.body)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(.primary)

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

// MARK: - Gradient helper (shared with PlayerView)

func categoryGradient(for category: String) -> LinearGradient {
    switch category {
    case "Classical":
        return LinearGradient(colors: [Color(red: 0.42, green: 0.20, blue: 0.80),
                                       Color(red: 0.62, green: 0.10, blue: 0.52)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    case "Audiobooks":
        return LinearGradient(colors: [Color(red: 0.55, green: 0.35, blue: 0.10),
                                       Color(red: 0.80, green: 0.55, blue: 0.20)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    case "Contemporary":
        return LinearGradient(colors: [Color(red: 0.20, green: 0.40, blue: 0.20),
                                       Color(red: 0.35, green: 0.65, blue: 0.30)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    case "Lectures":
        return LinearGradient(colors: [Color(red: 0.00, green: 0.13, blue: 0.28),
                                       Color(red: 0.50, green: 0.38, blue: 0.10)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    case "News":
        return LinearGradient(colors: [Color(red: 0.10, green: 0.20, blue: 0.40),
                                       Color(red: 0.20, green: 0.40, blue: 0.60)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    default:
        return LinearGradient(colors: [Color.gray, Color.gray.opacity(0.6)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
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
