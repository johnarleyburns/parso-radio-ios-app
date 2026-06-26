import Foundation

@MainActor
final class SleepTimerController {
    private var sleepTimerTask: Task<Void, Never>? = nil
    private weak var playerVM: PlayerViewModel?

    init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard let vm = playerVM else { return }
        guard minutes > 0 else { return }
        let endsAt = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        vm.sleepTimerEndsAt = endsAt
        sleepTimerTask = Task { [weak self] in
            let interval = endsAt.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let vm = self.playerVM else { return }
                vm.audioPlayer.pause()
                vm.isPlaying = false
                vm.sleepTimerEndsAt = nil
                self.sleepTimerTask = nil
            }
        }
    }

    func setSleepAtEndOfTrack(_ on: Bool) {
        cancelSleepTimer()
        playerVM?.sleepAtEndOfTrack = on
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        playerVM?.sleepTimerEndsAt = nil
        playerVM?.sleepAtEndOfTrack = false
    }

    var isSleepTimerActive: Bool {
        (playerVM?.sleepTimerEndsAt != nil) == true || playerVM?.sleepAtEndOfTrack == true
    }
}
