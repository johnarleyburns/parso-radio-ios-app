import Foundation

@MainActor
final class AuditionController {
    private weak var playerVM: PlayerViewModel?

    init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    func auditTrack(_ track: Track) async {
        guard let vm = playerVM else { return }
        if !vm.isAuditioning {
            vm.preAuditionState = (
                channel: vm.currentChannel, playlist: vm.currentPlaylist,
                playlistTracks: vm.playlistTracks, playlistIndex: vm.playlistIndex,
                playHistory: vm.playHistory, shuffleMode: vm.shuffleMode,
                track: vm.currentTrack, position: vm.currentPosition, isPlaying: vm.isPlaying
            )
        }
        vm.isAuditioning = true
        vm.audioPlayer.isAuditioning = true
        vm.currentChannel = nil
        vm.currentPlaylist = nil
        vm.playlistTracks = []
        vm.playlistIndex = 0
        vm.playbackContextToken &+= 1
        vm.playHistory = []
        vm.channelDescription = vm.preAuditionState?.channel?.name ?? ""
        vm.beginTransition(pre: track)
        await Task.yield()
        await vm.playTrack(track, seekTo: nil, recordHistory: false)
    }

    func stopAudition() {
        guard let vm = playerVM else { return }
        guard vm.currentChannel == nil, vm.currentPlaylist == nil else { return }
        guard vm.currentTrack != nil || vm.isLoading || vm.preAuditionState != nil else { return }
        vm.stallWatchdog?.cancel()
        vm.stallWatchdog = nil
        vm.audioPlayer.skip()
        vm.currentTrack = nil
        vm.trackDuration = nil
        vm.isPlaying = false
        vm.isLoading = false
        vm.loadingMessage = nil
        vm.failedAuditionTrackId = nil
        vm.errorMessage = nil
        vm.playbackContextToken &+= 1
        vm.isAuditioning = false
        vm.audioPlayer.isAuditioning = false

        guard let pre = vm.preAuditionState else { return }
        vm.preAuditionState = nil
        vm.currentChannel = pre.channel
        vm.currentPlaylist = pre.playlist
        vm.playlistTracks = pre.playlistTracks
        vm.playlistIndex = pre.playlistIndex
        vm.playHistory = pre.playHistory
        vm.shuffleMode = pre.shuffleMode
        if let track = pre.track {
            Task {
                await vm.playTrack(track, seekTo: pre.position > 1 ? pre.position : nil,
                                    recordHistory: false, autoPlay: false)
            }
        } else if let channel = pre.channel {
            Task { await vm.load(channel: channel, autoPlay: false) }
        } else if let playlist = pre.playlist {
            Task { await vm.loadPlaylist(playlist, autoPlay: false) }
        }
    }

    func stopAuditionWithoutRestore() {
        guard let vm = playerVM else { return }
        guard vm.currentChannel == nil, vm.currentPlaylist == nil,
              (vm.currentTrack != nil || vm.isLoading) else { return }
        vm.stallWatchdog?.cancel()
        vm.stallWatchdog = nil
        vm.audioPlayer.skip()
        vm.currentTrack = nil
        vm.trackDuration = nil
        vm.isPlaying = false
        vm.isLoading = false
        vm.loadingMessage = nil
        vm.failedAuditionTrackId = nil
        vm.errorMessage = nil
        vm.playbackContextToken &+= 1
    }
}
