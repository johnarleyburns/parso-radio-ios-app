import SwiftUI

struct SleepTimerControl: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    var showLabel: Bool = true

    var body: some View {
        Menu {
            Button("15 min") { playerVM.startSleepTimer(minutes: 15) }
            Button("30 min") { playerVM.startSleepTimer(minutes: 30) }
            Button("45 min") { playerVM.startSleepTimer(minutes: 45) }
            Button("60 min") { playerVM.startSleepTimer(minutes: 60) }
            Divider()
            Button("End of Track") { playerVM.setSleepAtEndOfTrack(true) }
            if playerVM.isSleepTimerActive {
                Divider()
                Button("Cancel Timer", role: .destructive) {
                    playerVM.cancelSleepTimer()
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: playerVM.isSleepTimerActive
                      ? "moon.zzz.fill" : "moon.zzz")
                    .font(.title3)
                if showLabel { Text("Sleep Timer").font(.caption2) }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(playerVM.isSleepTimerActive ? Color.accentColor : .primary)
        }
        .accessibilityLabel("Sleep Timer")
    }
}
