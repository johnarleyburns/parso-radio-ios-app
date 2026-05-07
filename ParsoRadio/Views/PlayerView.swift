import SwiftUI

struct PlayerView: View {
    let channel: Channel
    @EnvironmentObject var playerVM: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    artwork
                        .padding(.top, 32)

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

                    Spacer(minLength: 32)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await playerVM.load(channel: channel)
        }
    }

    // MARK: - Artwork

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(categoryGradient(for: channel.category))
                .frame(width: 260, height: 260)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 8)

            if playerVM.isLoading && playerVM.currentTrack == nil {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    if let msg = playerVM.loadingMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            } else {
                Image(systemName: channel.icon)
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .opacity(playerVM.isLoading && playerVM.currentTrack != nil ? 0.75 : 1)
        .animation(.easeInOut(duration: 0.3), value: playerVM.isLoading)
    }

    // MARK: - Track info

    @ViewBuilder
    private var trackInfo: some View {
        if let track = playerVM.currentTrack {
            VStack(spacing: 6) {
                Text(track.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let composer = track.composer, composer != track.artist.lowercased() {
                    Text("Composed by \(composer.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if playerVM.isLoading, let msg = playerVM.loadingMessage {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 8) {
                        licenseTag(track.license)
                        sourceTag(track.source)
                    }
                    .padding(.top, 4)
                }
            }
        } else if !playerVM.isLoading {
            Text("No tracks available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 16) {
            // Progress bar + time — only for spoken-word channels with known duration.
            if channel.contentType == .spokenWord {
                progressBar
            }

            HStack(spacing: 56) {
                Button {
                    playerVM.skip()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.primary)
                }

                Button {
                    playerVM.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(categoryGradient(for: channel.category))
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: playerVM.isPlaying ? 0 : 2)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            if let duration = playerVM.trackDuration, duration > 0 {
                ProgressView(value: playerVM.currentPosition, total: duration)
                    .tint(categoryGradient(for: channel.category).stops.first?.color ?? .accentColor)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            HStack {
                Text(formatTime(playerVM.currentPosition))
                Spacer()
                if let duration = playerVM.trackDuration {
                    Text(formatTime(duration))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.horizontal, 4)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Labels

    @ViewBuilder
    private func licenseTag(_ license: LicenseType) -> some View {
        switch license {
        case .cc0:
            badge("CC0", color: .blue)
        case .ccBy:
            badge("CC BY", color: .orange)
        case .publicDomain:
            badge("Public Domain", color: .green)
        case .rejected:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sourceTag(_ source: String) -> some View {
        switch source {
        case "fma":
            badge("Free Music Archive", color: .gray)
        case "musopen":
            badge("Musopen", color: .purple)
        default:
            badge("Internet Archive", color: .gray)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        PlayerView(channel: Channel.defaults[0])
            .environmentObject(PlayerViewModel(
                db: try! DatabaseService(path: ":memory:"),
                archiveService: InternetArchiveService(),
                fmaService: FMAService(),
                queueManager: QueueManager(db: try! DatabaseService(path: ":memory:")),
                audioPlayer: AudioPlayerService(),
                downloadManager: DownloadManager(db: try! DatabaseService(path: ":memory:"))
            ))
    }
}
