import Foundation

protocol DatabaseServiceProtocol: AnyObject {
    // Track operations
    func saveTracks(_ newTracks: [Track]) async
    func pruneChannelTracks(forChannel channel: Channel, keeping freshIds: Set<String>) async
    func markDownloaded(trackID: String, localPath: String) async
    func fetchTracks(forChannel channel: Channel) async -> [Track]
    func fetchTrack(id: String) async -> Track?
    func fetchTracks(forParentIdentifier parentId: String) async -> [Track]
    func deleteTracks(forParentIdentifier parentId: String) async
    func setIsMultiPart(_ value: Bool?, forTrackId id: String) async
    func fetchDownloadedTracks(forChannel channel: Channel) async -> [Track]
    func evictOldTracks(olderThan days: Int) async
    func trackCount() async -> Int

    // Curation operations
    func setCuration(channelId: String, trackId: String, status: String, note: String?) async
    func curationStatus(channelId: String, trackId: String) async -> String?
    func curationTrackIds(channelId: String, status: String) async -> [String]
    func curationCounts(channelId: String) async -> (review: Int, approved: Int, rejected: Int)
    func fetchApprovedTracks(forChannelId channelId: String) async -> [Track]
    func fetchRejectedTracks(forChannelId channelId: String) async -> [Track]
    func exportApprovedByChannel() async -> [String: [Track]]
    func ensureReviewSet(channelId: String, trackIds: [String]) async
    func reviewSetTracks(channelId: String) async -> [Track]

    // Position persistence
    func savePosition(channelId: String, trackId: String, seconds: Double) async
    func loadPosition(channelId: String) async -> (trackId: String, seconds: Double)?
    func clearPosition(channelId: String) async

    // Playlist operations
    func createPlaylist(name: String, isFavorites: Bool) async throws -> Playlist
    func fetchPlaylists() async -> [Playlist]
    func setPlaylistOrder(_ ids: [String]) async
    func renamePlaylist(id: String, name: String) async
    func setPlaylistKidSafe(id: String, isKidSafe: Bool) async
    func deletePlaylist(id: String) async
    func addTrack(_ track: Track, toPlaylist playlistId: String) async
    func addTracksOrdered(_ orderedTracks: [Track], toPlaylist playlistId: String) async
    func removeTrack(trackId: String, fromPlaylist playlistId: String) async
    func playlistIDsWithDownloads() async -> Set<String>
    func fetchTracks(forPlaylist playlistId: String) async -> [Track]
    func setTrackOrder(_ trackIds: [String], inPlaylist playlistId: String) async
    func isTrack(_ trackId: String, inPlaylist playlistId: String) async -> Bool

    // Play history
    func recordPlayed(channelId: String, trackId: String) async
    func recentlyHeardIds(forChannel channelId: String, withinDays days: Int) async -> Set<String>
    func deletePlayHistory(trackId: String) async
    func clearAllPlayHistory() async
    func wipeAllData() async
    func evictOldPlayHistory(olderThanDays days: Int) async
    func lastPlayedTrack(forChannel channelId: String) async -> Track?
    func fetchRecentlyPlayedTracks(limit: Int) async -> [Track]
    func fetchRecentlyPlayedWithChannel(limit: Int) async -> [(track: Track, channelId: String)]

    // Bookmarks
    func saveBookmark(_ bookmark: Bookmark) async
    func fetchBookmarks(forTrack trackId: String) async -> [Bookmark]
    func deleteBookmark(id: String) async
    func deleteAllBookmarks(forTrack trackId: String) async
    func saveAutosaveBookmark(trackId: String, positionSeconds: Double, createdAt: Date) async
    func fetchAutosaveBookmark(forTrack trackId: String) async -> Bookmark?
    func deleteAutosaveBookmark(forTrack trackId: String) async

    // Offline counts
    func offlineTrackCount(forChannel channel: Channel) async -> Int
    func offlineTrackCount(forPlaylist playlistId: String) async -> Int

    // Podcast subscriptions
    func fetchPodcastSubscriptions() async -> [PodcastSubscription]
    func savePodcastSubscription(_ sub: PodcastSubscription) async
    func deletePodcastSubscription(_ sub: PodcastSubscription) async

    // Track metadata enrichment
    func saveTrackMetadata(_ meta: TrackMetadata) async
    func fetchTrackMetadata(trackID: String) async -> TrackMetadata?
    func fetchUnenrichedApprovedTrackIDs(channelId: String) async -> [String]
}
