import Foundation

@MainActor
final class SleepTimerController {
    private var sleepTimerTask: Task<Void, Never>? = nil
    private weak var playerVM: PlayerViewModel?
    /// True while the wall-clock fade-out is in progress (audio is ramping to
    /// silence but the VM still reports playing). Lets `cancelSleepTimer` abort
    /// the fade and restore full volume if the user cancels mid-fade.
    private var isFadingForSleep = false
    /// Wake this many seconds before expiry to fade out gently. Timers shorter
    /// than this just pause at the boundary (no time to fade).
    private let fadeLeadSeconds: TimeInterval = 10

    init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard let vm = playerVM else { return }
        guard minutes > 0 else { return }
        let total = TimeInterval(minutes) * 60
        let endsAt = Date().addingTimeInterval(total)
        vm.sleepTimerEndsAt = endsAt
        // Long enough to fade? Wake `fadeLeadSeconds` early and ramp out gently;
        // otherwise pause exactly at the boundary.
        let fadeLead = total > fadeLeadSeconds ? fadeLeadSeconds : 0
        sleepTimerTask = Task { [weak self] in
            let wait = endsAt.timeIntervalSinceNow - fadeLead
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let vm = self.playerVM else { return }
                guard fadeLead > 0 else {
                    vm.audioPlayer.pause()
                    vm.isPlaying = false
                    vm.sleepTimerEndsAt = nil
                    self.sleepTimerTask = nil
                    return
                }
                // Begin the fade; keep `isPlaying` true so the UI (and a cancel)
                // still treat audio as live until the ramp completes.
                self.isFadingForSleep = true
                vm.audioPlayer.fadeOutThenPause(duration: fadeLead)
            }
            guard fadeLead > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(fadeLead * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let vm = self.playerVM else { return }
                self.isFadingForSleep = false
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
        let wasFading = isFadingForSleep
        isFadingForSleep = false
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        playerVM?.sleepTimerEndsAt = nil
        playerVM?.sleepAtEndOfTrack = false
        // Cancelled mid-fade while still nominally playing → abort the fade and
        // restore full volume so the user keeps listening at normal level.
        if wasFading, let vm = playerVM, vm.isPlaying {
            vm.audioPlayer.resume()
        }
    }

    var isSleepTimerActive: Bool {
        (playerVM?.sleepTimerEndsAt != nil) == true || playerVM?.sleepAtEndOfTrack == true
    }
}
