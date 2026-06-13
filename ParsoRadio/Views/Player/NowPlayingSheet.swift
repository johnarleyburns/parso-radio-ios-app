import SwiftUI

struct NowPlayingSheet: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    artwork
                        .padding(.top, 16)

                    trackInfo

                    if let channel = playerVM.currentChannel {
                        behaviorComposedControls(for: channel)
                    }

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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let channel = playerVM.currentChannel {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(ChannelCategoryStyle.gradient(for: channel.category))
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
    }

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
                        ProgressView().scaleEffect(0.7)
                        Text(msg).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 8) {
                        LicenseDisplay.label(track.license)
                        SourceDisplay.tag(track.source)
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

    @ViewBuilder
    private func behaviorComposedControls(for channel: Channel) -> some View {
        let b = channel.behavior
        VStack(spacing: 16) {
            if b.showsScrubbableProgress {
                ScrubBar(tint: ChannelCategoryStyle.color(for: channel.category))
            }

            TransportControls(tint: ChannelCategoryStyle.color(for: channel.category))
                .disabled(playerVM.isLoading)

            HStack(spacing: 20) {
                if b.allowsShuffleToggle { ShuffleToggle() }
                if b.supportsSpeedControl { SpeedControl() }
                if b.supportsSleepTimer { SleepTimerControl() }
            }

            HStack(spacing: 20) {
                if b.supportsChapters { ChapterButton() }
                if b.supportsBookmarks { BookmarkButton() }
            }

            if b.supportsBookSkip { BookSkipControls() }
        }
    }
}
