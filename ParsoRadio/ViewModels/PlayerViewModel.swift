import Foundation
import UIKit

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String?
    @Published var errorMessage: String?
    @Published var currentPosition: Double = 0
    @Published var trackDuration: Double?
    @Published var isScrubbing: Bool = false

    let audioPlayer: AudioPlayerService

    private let db: DatabaseService
    private let archiveService: InternetArchiveService
    private let fmaService: FMAService
    private let oxfordService: OxfordLecturesService
    private let queueManager: QueueManager
    private let downloadManager: DownloadManager
    var currentChannel: Channel?

    // Look-ahead cache: pre-resolved IA audio URLs so track transitions are gap-free.
    private var prefetchedURLs: [String: URL] = [:]

    // UC3: track history for backward navigation (most-recent last, cap historyLimit).
    var playHistory: [Track] = []
    let historyLimit = 50

    init(
        db: DatabaseService,
        archiveService: InternetArchiveService,
        fmaService: FMAService,
        queueManager: QueueManager,
        audioPlayer: AudioPlayerService,
        downloadManager: DownloadManager,
        oxfordService: OxfordLecturesService = OxfordLecturesService()
    ) {
        self.db = db
        self.archiveService = archiveService
        self.fmaService = fmaService
        self.oxfordService = oxfordService
        self.queueManager = queueManager
        self.audioPlayer = audioPlayer
        self.downloadManager = downloadManager

        audioPlayer.onPreviousTrack = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.playPreviousTrack()
            }
        }

        audioPlayer.onTrackFinished = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Natural finish: clear saved position so the next track starts fresh.
                if let channel = self.currentChannel, channel.contentType == .spokenWord {
                    await self.db.clearPosition(channelId: channel.id)
                }
                await self.advanceToNext()
            }
        }

        audioPlayer.onTimeUpdate = { [weak self] seconds in
            Task { @MainActor [weak self] in
                guard let self, !self.isScrubbing else { return }
                self.currentPosition = seconds
                self.trackDuration = self.audioPlayer.duration
                // Persist position for spoken-word channels so the user can resume.
                if let channel = self.currentChannel,
                   channel.contentType == .spokenWord,
                   let track = self.currentTrack {
                    await self.db.savePosition(
                        channelId: channel.id,
                        trackId: track.id,
                        seconds: seconds
                    )
                }
            }
        }
    }

    func load(channel: Channel) async {
        // UC5: stop any currently playing audio immediately so old track doesn't bleed into new channel.
        audioPlayer.skip()
        currentTrack = nil
        isPlaying = false
        // UC2: persist last-used channel so the app restores it after restart.
        UserDefaults.standard.set(channel.id, forKey: "lastChannelId")
        // UC6: track visited channels for Favorites (MRU, capped at 20).
        var visited = UserDefaults.standard.stringArray(forKey: "visitedChannelIds") ?? []
        visited.removeAll { $0 == channel.id }
        visited.insert(channel.id, at: 0)
        if visited.count > 20 { visited = Array(visited.prefix(20)) }
        UserDefaults.standard.set(visited, forKey: "visitedChannelIds")

        currentChannel = channel
        isLoading = true
        loadingMessage = "Finding tracks…"
        errorMessage = nil
        currentPosition = 0
        trackDuration = nil

        do {
            let fetched: [Track]

            if channel.category == "Oxford Lectures" {
                // UC13: Oxford channels fetch from podcasts.ox.ac.uk via OxfordLecturesService.
                fetched = try await oxfordService.fetchTracks(unitSlug: channel.tags.first ?? "")
            } else if channel.contentType == .spokenWord {
                // Spoken-word channels: LibriVox / podcast collections via IA.
                fetched = try await archiveService.fetchSpokenWordTracks(channel: channel)
            } else if channel.composers.isEmpty {
                // Tag channels: IA + FMA in parallel; FMA errors are non-fatal.
                async let iaTracks = archiveService.fetchTracks(tags: channel.tags)
                let fmaTracks = (try? await fmaService.fetchTracks(forChannel: channel)) ?? []
                let iaResults = try await iaTracks
                var seen = Set<String>()
                fetched = (iaResults + fmaTracks).filter { seen.insert($0.id).inserted }
            } else {
                // Composer channels: IA + Musopen(IA) + FMA all in parallel.
                async let iaTracks = archiveService.fetchTracks(
                    composers: channel.composers,
                    instruments: channel.instruments
                )
                var supplemental: [Track] = []
                await withTaskGroup(of: [Track].self) { group in
                    for composer in channel.composers {
                        group.addTask { (try? await self.archiveService.fetchMusopenTracks(composer: composer)) ?? [] }
                    }
                    group.addTask { (try? await self.fmaService.fetchTracks(forChannel: channel)) ?? [] }
                    for await tracks in group { supplemental.append(contentsOf: tracks) }
                }
                let iaResults = try await iaTracks
                var seen = Set<String>()
                fetched = (iaResults + supplemental).filter { seen.insert($0.id).inserted }
            }

            await db.saveTracks(fetched)
            downloadManager.prefetchNext(fetched)
        } catch {
            if currentTrack == nil {
                errorMessage = "Could not refresh tracks."
            }
        }

        // Resume the last-played track for all channel types.
        // Spoken-word resumes at exact position; music restarts the same track from the beginning.
        if let saved = await db.loadPosition(channelId: channel.id),
           let track = await db.fetchTrack(id: saved.trackId) {
            loadingMessage = "Resuming…"
            let seekTo: Double? = channel.contentType == .spokenWord ? saved.seconds : nil
            await playTrack(track, seekTo: seekTo)
        } else {
            loadingMessage = "Starting playback…"
            await advanceToNext()
        }

        isLoading = false
        loadingMessage = nil
    }

    func togglePlayPause() {
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            isPlaying = false
        } else if currentTrack != nil {
            audioPlayer.resume()
            isPlaying = true
        }
    }

    func skip() {
        guard let channel = currentChannel else {
            audioPlayer.skip()
            isPlaying = false
            Task { await advanceToNext() }
            return
        }
        if channel.category == "Oxford Lectures" {
            // UC14: Oxford forward always advances to the next lecture, never seeks +30 s.
            audioPlayer.skip()
            isPlaying = false
            Task {
                await db.clearPosition(channelId: channel.id)
                await advanceToNext()
            }
        } else if channel.contentType == .spokenWord {
            // UC8: for spoken-word, forward skips +30 s within the chapter.
            // At the end of the chapter it advances to the next one.
            let target = currentPosition + 30
            if let dur = audioPlayer.duration, target < dur {
                audioPlayer.seek(to: target)
                currentPosition = target
            } else {
                audioPlayer.skip()
                isPlaying = false
                Task {
                    await db.clearPosition(channelId: channel.id)
                    await advanceToNext()
                }
            }
        } else {
            audioPlayer.skip()
            isPlaying = false
            Task { await advanceToNext() }
        }
    }

    func seek(to seconds: Double) {
        audioPlayer.seek(to: seconds)
        currentPosition = seconds
    }

    func back() {
        guard let channel = currentChannel else { return }
        if channel.contentType == .spokenWord {
            // Rewind 15 s within the chapter; go to previous track if already at start.
            if currentPosition > 3 {
                let target = max(0, currentPosition - 15)
                audioPlayer.seek(to: target)
                currentPosition = target
            } else {
                Task { await playPreviousTrack() }
            }
        } else {
            // UC3: restart the current track if well into it; go to previous if near the start.
            if currentPosition > 3 {
                audioPlayer.seek(to: 0)
                currentPosition = 0
            } else {
                Task { await playPreviousTrack() }
            }
        }
    }

    // MARK: - Private

    private func advanceToNext() async {
        guard let channel = currentChannel else { return }

        // Assert a background task so iOS doesn't kill the network call that
        // resolves the next track URL when the app is backgrounded.
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "advance-track") {
            UIApplication.shared.endBackgroundTask(bgTask)
        }
        defer { UIApplication.shared.endBackgroundTask(bgTask) }

        guard let track = await queueManager.nextTrack(channel: channel) else {
            currentTrack = nil
            isPlaying = false
            if errorMessage == nil {
                errorMessage = "No tracks available for this channel."
            }
            isLoading = false
            return
        }
        await playTrack(track, seekTo: nil)
    }

    private func playPreviousTrack() async {
        guard !playHistory.isEmpty else {
            // No history: restart the current track from the beginning.
            audioPlayer.seek(to: 0)
            currentPosition = 0
            return
        }
        let previous = playHistory.removeLast()
        await playTrack(previous, seekTo: nil, recordHistory: false)
    }

    private func playTrack(_ track: Track, seekTo: Double?, recordHistory: Bool = true) async {
        // UC3: push current track onto history before replacing it.
        if recordHistory, let existing = currentTrack {
            playHistory.append(existing)
            if playHistory.count > historyLimit { playHistory.removeFirst() }
        }
        currentTrack = track
        isLoading = true
        loadingMessage = track.source == "internet_archive" ? "Buffering…" : "Loading…"
        defer {
            isLoading = false
            loadingMessage = nil
        }

        do {
            let url: URL
            if let localPath = track.localFilePath,
               FileManager.default.fileExists(atPath: localPath) {
                url = URL(fileURLWithPath: localPath)
            } else if track.source == "internet_archive" {
                if let cached = prefetchedURLs.removeValue(forKey: track.id) {
                    url = cached
                } else {
                    url = try await archiveService.resolveAudioURL(for: track.id)
                }
            } else {
                url = track.streamURL
            }
            audioPlayer.play(url: url, track: track)
            if let seconds = seekTo, seconds > 0 {
                audioPlayer.seek(to: seconds)
                currentPosition = seconds
            }
            isPlaying = true
            errorMessage = nil

            if let channel = currentChannel {
                // Save current track for music channels so it can be resumed after restart.
                // Spoken-word position is kept current by the onTimeUpdate callback.
                if channel.contentType != .spokenWord {
                    await db.savePosition(channelId: channel.id, trackId: track.id, seconds: 0)
                }
                Task { await prefetchNextURL(channel: channel) }
            }
        } catch {
            errorMessage = "Could not load \"\(track.title)\"."
            isPlaying = false
        }
    }

    private func prefetchNextURL(channel: Channel) async {
        guard let next = await queueManager.peekNextTrack(channel: channel),
              next.source == "internet_archive",
              prefetchedURLs[next.id] == nil else { return }
        if let url = try? await archiveService.resolveAudioURL(for: next.id) {
            prefetchedURLs[next.id] = url
        }
    }
}
