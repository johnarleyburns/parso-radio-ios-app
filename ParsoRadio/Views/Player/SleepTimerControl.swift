import SwiftUI

struct SleepTimerControl: View {
    @EnvironmentObject var playerVM: PlayerViewModel

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
            Label("Sleep Timer", systemImage: playerVM.isSleepTimerActive
                  ? "moon.zzz.fill" : "moon.zzz")
                .font(.caption)
        }
    }
}
