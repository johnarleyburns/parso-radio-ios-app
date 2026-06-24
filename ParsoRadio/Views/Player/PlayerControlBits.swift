import SwiftUI

struct TransportButton: View {
    let system: String
    var size: CGFloat = 26
    let label: String
    var prominent: Bool = false
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if prominent {
                Image(systemName: system)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size + 34, height: size + 34)
                    .background(tint, in: Circle())
            } else {
                Image(systemName: system)
                    .font(.system(size: size, weight: .semibold))
                    .frame(width: size + 22, height: size + 22)
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ScrubRow: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    let tint: Color
    var showTimeLeftInWork: Bool = false
    var isLecture: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ScrubBar(tint: tint)
            HStack {
                Text(playerVM.currentPosition.formattedTime)
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("Elapsed time")
                    .accessibilityIdentifier("player.elapsed")
                Spacer()
                if showTimeLeftInWork, let left = playerVM.timeLeftInBook {
                    Text("\(isLecture ? "Series" : "Book") \(left.formattedTime) left")
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("\(isLecture ? "Series" : "Book") time left")
                        .accessibilityIdentifier("player.work-time-left")
                    Spacer()
                }
                let remaining = (playerVM.trackDuration ?? 0) - playerVM.currentPosition
                Text("-\(remaining.formattedTime)")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("Remaining time")
                    .accessibilityIdentifier("player.remaining")
            }
        }
    }
}

struct ShuffleButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var body: some View {
        Button { playerVM.toggleShuffle() } label: {
            Image(systemName: "shuffle").font(.body)
                .foregroundStyle(playerVM.shuffleMode ? Color.accentColor : .secondary)
        }
        .accessibilityLabel(playerVM.shuffleMode ? "Shuffle on" : "Shuffle off")
    }
}

struct RepeatButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var body: some View {
        Button { playerVM.toggleRepeat() } label: {
            Image(systemName: playerVM.repeatMode == .one ? "repeat.1" : "repeat").font(.body)
                .foregroundStyle(playerVM.repeatMode == .one ? Color.accentColor : .secondary)
        }
        .accessibilityLabel(playerVM.repeatMode == .one ? "Repeat one" : "Repeat off")
    }
}

struct SleepTimerButton: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var showLabel: Bool = false
    var body: some View {
        Menu {
            Button("15 minutes") { playerVM.startSleepTimer(minutes: 15) }
            Button("30 minutes") { playerVM.startSleepTimer(minutes: 30) }
            Button("45 minutes") { playerVM.startSleepTimer(minutes: 45) }
            Button("1 hour")     { playerVM.startSleepTimer(minutes: 60) }
            Divider()
            Button("End of track") { playerVM.setSleepAtEndOfTrack(true) }
            if playerVM.isSleepTimerActive {
                Divider()
                Button("Cancel timer", role: .destructive) { playerVM.cancelSleepTimer() }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: playerVM.isSleepTimerActive ? "moon.zzz.fill" : "moon.zzz").font(.title3)
                if showLabel { Text("Sleep").font(.caption2) }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(playerVM.isSleepTimerActive ? Color.accentColor : .primary)
        }
        .accessibilityLabel("Sleep timer")
    }
}
