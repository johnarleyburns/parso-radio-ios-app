import SwiftUI

struct PlayerView: View {
    let channel: Channel
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            trackInfo

            controls
                .disabled(playerVM.isLoading)

            if let msg = playerVM.errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await playerVM.load(channel: channel)
        }
    }

    @ViewBuilder
    private var trackInfo: some View {
        if playerVM.isLoading && playerVM.currentTrack == nil {
            ProgressView()
                .scaleEffect(1.5)
        } else if let track = playerVM.currentTrack {
            VStack(spacing: 8) {
                Text(track.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                licenseLabel(track.license)
            }
        } else {
            Text("No tracks available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 48) {
            Button {
                playerVM.skip()
            } label: {
                Image(systemName: "forward.fill")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.primary)
            }

            Button {
                playerVM.togglePlayPause()
            } label: {
                Image(systemName: playerVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func licenseLabel(_ license: LicenseType) -> some View {
        switch license {
        case .cc0:
            Text("CC0 — No Rights Reserved")
                .font(.caption).foregroundStyle(.secondary)
        case .ccBy:
            Text("CC BY — Attribution Required")
                .font(.caption).foregroundStyle(.secondary)
        case .publicDomain:
            Text("Public Domain")
                .font(.caption).foregroundStyle(.secondary)
        case .rejected:
            EmptyView()
        }
    }
}

#Preview {
    PlayerView(channel: Channel.defaults[0])
        .environmentObject(PlayerViewModel(
            db: try! DatabaseService(path: ":memory:"),
            archiveService: InternetArchiveService(),
            queueManager: QueueManager(db: try! DatabaseService(path: ":memory:")),
            audioPlayer: AudioPlayerService(),
            downloadManager: DownloadManager(db: try! DatabaseService(path: ":memory:"))
        ))
}
