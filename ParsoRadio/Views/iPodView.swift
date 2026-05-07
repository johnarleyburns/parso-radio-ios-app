import SwiftUI

struct iPodView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var pendingChannel: Channel = Channel.defaults.first { $0.id == "bach-vivaldi-strings" } ?? Channel.defaults[0]
    @State private var showChannelSelector = false
    @State private var showAbout = false
    @State private var wheelTapTrigger = 0

    private var displayChannel: Channel {
        playerVM.currentChannel ?? pendingChannel
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                channelLabel
                    .padding(.top, 20)

                Spacer(minLength: 16)

                ClickWheel(
                    isPlaying: playerVM.isPlaying,
                    onMenu:      { wheelTapTrigger += 1; showChannelSelector = true },
                    onBack:      { wheelTapTrigger += 1; playerVM.back() },
                    onForward:   { wheelTapTrigger += 1; playerVM.skip() },
                    onPlayPause: { wheelTapTrigger += 1; playerVM.togglePlayPause() }
                )
                .frame(width: 280, height: 280)
                .sensoryFeedback(.impact(.light), trigger: wheelTapTrigger)

                Spacer(minLength: 20)

                nowPlayingCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showAbout = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .sheet(isPresented: $showChannelSelector) {
            ChannelSelectorView(currentChannelId: displayChannel.id) { channel in
                pendingChannel = channel
                showChannelSelector = false
                Task { await playerVM.load(channel: channel) }
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .task {
            await playerVM.load(channel: pendingChannel)
        }
    }

    // MARK: - Channel label

    private var channelLabel: some View {
        VStack(spacing: 3) {
            Text(displayChannel.name)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .animation(.spring(duration: 0.25), value: displayChannel.id)
            Text(displayChannel.category)
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.spring(duration: 0.25), value: displayChannel.category)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Now-playing card

    @ViewBuilder
    private var nowPlayingCard: some View {
        if let track = playerVM.currentTrack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    channelArtwork
                        .opacity(playerVM.isLoading ? 0.6 : 1)
                        .animation(.easeInOut(duration: 0.25), value: playerVM.isLoading)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if playerVM.isLoading, let msg = playerVM.loadingMessage {
                            HStack(spacing: 5) {
                                ProgressView().scaleEffect(0.65)
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        } else {
                            licenseRow(track.license, source: track.source)
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 0)
                }

                if displayChannel.contentType == .spokenWord,
                   let dur = playerVM.trackDuration, dur > 0 {
                    VStack(spacing: 3) {
                        ProgressView(value: playerVM.currentPosition, total: dur)
                            .tint(progressTint(for: displayChannel.category))
                        HStack {
                            Text(formatTime(playerVM.currentPosition))
                            Spacer()
                            Text(formatTime(dur))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    .padding(.top, 10)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        } else if playerVM.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text(playerVM.loadingMessage ?? "Loading…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        } else if let err = playerVM.errorMessage {
            Text(err)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding()
        } else {
            // Placeholder before first load
            HStack(spacing: 12) {
                channelArtwork
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap MENU to select a channel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var channelArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(categoryGradient(for: displayChannel.category))
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            Image(systemName: displayChannel.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func licenseRow(_ license: LicenseType, source: String) -> some View {
        HStack(spacing: 6) {
            switch license {
            case .cc0:          badge("CC0", color: .blue)
            case .ccBy:         badge("CC BY", color: .orange)
            case .publicDomain: badge("Public Domain", color: .green)
            case .rejected:     EmptyView()
            }
            switch source {
            case "fma":     badge("FMA", color: .gray)
            case "musopen": badge("Musopen", color: .purple)
            default:        badge("Archive.org", color: .gray)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func progressTint(for category: String) -> Color {
        switch category {
        case "Classical":          return Color(red: 0.42, green: 0.20, blue: 0.80)
        case "Jazz & Blues":       return Color(red: 0.10, green: 0.22, blue: 0.65)
        case "Rock & Country":     return Color(red: 0.72, green: 0.10, blue: 0.10)
        case "Vibes":              return Color(red: 0.08, green: 0.50, blue: 0.40)
        case "Talk & Stories":     return Color(red: 0.55, green: 0.35, blue: 0.10)
        case "Electronic & Beats": return Color(red: 0.05, green: 0.10, blue: 0.45)
        case "Pop & World":        return Color(red: 0.85, green: 0.20, blue: 0.55)
        default:                   return .accentColor
        }
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Click Wheel

struct ClickWheel: View {
    let isPlaying: Bool
    let onMenu:      () -> Void
    let onBack:      () -> Void
    let onForward:   () -> Void
    let onPlayPause: () -> Void

    var body: some View {
        GeometryReader { geo in
            let size    = min(geo.size.width, geo.size.height)
            let outerR  = size / 2
            let innerR  = size * 0.225   // center button radius ≈ 45% of total diameter
            let midRing = (outerR + innerR) / 2   // label placement

            ZStack {
                // Outer ring
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

                // Inner clickable circle
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: innerR * 2, height: innerR * 2)
                    .shadow(color: .black.opacity(0.10), radius: 5, y: 2)

                // MENU (top)
                Text("MENU")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .offset(y: -midRing)

                // Back (left)
                Image(systemName: "backward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .offset(x: -midRing)

                // Forward (right)
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .offset(x: midRing)

                // Play/Pause (bottom)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .offset(y: midRing)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        let dist = sqrt(dx * dx + dy * dy)

                        // Must be within the outer ring but outside the inner center button
                        guard dist <= outerR, dist > innerR else { return }

                        if abs(dy) >= abs(dx) {
                            if dy < 0 { onMenu() } else { onPlayPause() }
                        } else {
                            if dx < 0 { onBack() } else { onForward() }
                        }
                    }
            )
        }
    }
}

#Preview {
    iPodView()
        .environmentObject(PlayerViewModel(
            db: try! DatabaseService(path: ":memory:"),
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: try! DatabaseService(path: ":memory:")),
            audioPlayer: AudioPlayerService(),
            downloadManager: DownloadManager(db: try! DatabaseService(path: ":memory:"))
        ))
}
