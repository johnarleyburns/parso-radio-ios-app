import SwiftUI

struct TransportControls: View {
    @EnvironmentObject var playerVM: PlayerViewModel

    private var behavior: PlaybackBehavior {
        playerVM.currentChannel?.behavior ?? MediaKind.music.behavior
    }

    private var bookSkipDisabled: Bool {
        playerVM.currentChannel == nil
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                if behavior.supportsBookSkip {
                    Button {
                        Task { await playerVM.skipToPreviousBook() }
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 30))
                    }
                    .accessibilityLabel("Previous book")
                    .buttonStyle(.plain)
                    .disabled(bookSkipDisabled)
                }

                Button {
                    Task { await playerVM.goToPreviousTrack() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 30))
                }
                .accessibilityLabel("Previous track")
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 28) {
                Button {
                    playerVM.seekBy(-10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }
                .accessibilityLabel("Back 10 seconds")
                .buttonStyle(.plain)

                Button {
                    playerVM.togglePlayPause()
                } label: {
                    Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }
                .accessibilityLabel(playerVM.isPlaying ? "Pause" : "Play")
                .buttonStyle(.plain)

                Button {
                    playerVM.seekBy(10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
                .accessibilityLabel("Forward 10 seconds")
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    playerVM.skip()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 30))
                }
                .accessibilityLabel("Next track")
                .buttonStyle(.plain)

                if behavior.supportsBookSkip {
                    Button {
                        Task { await playerVM.skipToNextBook() }
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 30))
                    }
                    .accessibilityLabel("Next book")
                    .buttonStyle(.plain)
                    .disabled(bookSkipDisabled)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
