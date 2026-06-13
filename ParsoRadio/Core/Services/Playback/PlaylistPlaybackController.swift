import Foundation

@MainActor
final class PlaylistPlaybackController {
    private let db: DatabaseService
    private weak var playerVM: PlayerViewModel?

    init(db: DatabaseService, playerVM: PlayerViewModel) {
        self.db = db
        self.playerVM = playerVM
    }

    static func playlistKey(_ playlistId: String) -> String { "playlist:\(playlistId)" }

    func loadPlaylist(_ playlist: Playlist,
                      startingAt track: Track? = nil,
                      seekTo: Double = 0,
                      shuffle: Bool = false,
                      autoPlay: Bool = true) async {
        guard let vm = playerVM else { return }
        vm.sessionRestore.saveAutosaveForCurrentTrack()
        vm.shuffleMode = shuffle
        vm.beginTransition(pre: track)
        vm.currentPlaylist = playlist
        vm.currentChannel = nil
        vm.playbackContextToken &+= 1
        vm.playHistory = []
        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        vm.playlistTracks = tracks
        vm.channelDescription = playlist.name
        vm.channelTrackCount = tracks.count
        vm.channelMostRecentDate = tracks.compactMap(\.addedDate).max()
        guard !tracks.isEmpty else { vm.playlistIndex = 0; return }
        let startTrack = track ?? tracks.first!
        vm.playlistIndex = track
            .flatMap { t in tracks.firstIndex(where: { $0.id == t.id }) } ?? 0
        await vm.playTrack(startTrack, seekTo: seekTo, recordHistory: false, autoPlay: autoPlay)
    }

    func savedPlaylistResume(_ playlist: Playlist) async -> (track: Track, seconds: Double)? {
        guard let saved = await db.loadPosition(channelId: Self.playlistKey(playlist.id))
        else { return nil }
        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        guard let track = tracks.first(where: { $0.id == saved.trackId }) else { return nil }
        return (track, saved.seconds)
    }

    func shufflePlaylist(_ playlist: Playlist) async {
        let tracks = await db.fetchTracks(forPlaylist: playlist.id)
        await loadPlaylist(playlist, startingAt: tracks.randomElement(), shuffle: true)
    }

    func resumePlaylist(_ playlist: Playlist, autoPlay: Bool = true) async {
        if let resume = await savedPlaylistResume(playlist) {
            await loadPlaylist(playlist, startingAt: resume.track, seekTo: resume.seconds,
                               autoPlay: autoPlay)
        } else {
            await loadPlaylist(playlist, autoPlay: autoPlay)
        }
    }

    func advancePlaylist() async {
        guard let vm = playerVM, !vm.playlistTracks.isEmpty else { return }
        if vm.shuffleMode, vm.playlistTracks.count > 1 {
            var i = Int.random(in: 0..<vm.playlistTracks.count)
            if i == vm.playlistIndex { i = (i + 1) % vm.playlistTracks.count }
            vm.playlistIndex = i
        } else {
            vm.playlistIndex = (vm.playlistIndex + 1) % vm.playlistTracks.count
        }
        await vm.playTrack(vm.playlistTracks[vm.playlistIndex], seekTo: nil, recordHistory: false)
    }
}
