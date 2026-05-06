import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var selectedChannel: Channel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Channel.defaults) { channel in
                        Button {
                            selectedChannel = channel
                        } label: {
                            Text(channel.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                                .background(Color(.systemGray6))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Parso Radio")
            .navigationDestination(item: $selectedChannel) { channel in
                PlayerView(channel: channel)
            }
        }
    }
}

#Preview {
    ChannelListView()
        .environmentObject(PlayerViewModel(
            db: try! DatabaseService(path: ":memory:"),
            archiveService: InternetArchiveService(),
            queueManager: QueueManager(db: try! DatabaseService(path: ":memory:")),
            audioPlayer: AudioPlayerService(),
            downloadManager: DownloadManager(db: try! DatabaseService(path: ":memory:"))
        ))
}
