import Foundation
import SQLite

// @unchecked Sendable: every database access is funnelled through the private
// serial `queue` below, so the otherwise non-Sendable SQLite `Connection` is
// only ever touched from one thread at a time. This is what lets the async
// wrappers capture `self` in their @Sendable continuation closures safely.
final class DatabaseService: @unchecked Sendable {
    private let db: Connection
    private let queue = DispatchQueue(label: "guru.parso.db", qos: .utility)

    // MARK: - Tracks table
    private let tracks        = Table("tracks")
    private let colId         = Expression<String>("id")
    private let colSource     = Expression<String>("source")
    private let colTitle      = Expression<String>("title")
    private let colArtist     = Expression<String>("artist")
    private let colDuration   = Expression<Double>("duration")
    private let colStreamURL  = Expression<String>("stream_url")
    private let colDownURL    = Expression<String?>("download_url")
    private let colLocalPath  = Expression<String?>("local_file_path")
    private let colLicense    = Expression<String>("license_type")
    private let colTags       = Expression<String>("tags")
    private let colQuality    = Expression<Double>("quality_score")
    private let colRawCreator = Expression<String>("raw_creator")
    private let colComposer   = Expression<String?>("composer")
    private let colInstruments = Expression<String>("instruments")
    private let colConfidence = Expression<Double>("metadata_confidence")
    private let colFetchedAt  = Expression<Int64>("fetched_at")

    // Tracks — new columns
    private let colAddedDate  = Expression<Double?>("added_date")
    private let colIsLocal    = Expression<Bool>("is_local")
    private let colPartNumber = Expression<Int?>("part_number")
    private let colTotalParts = Expression<Int?>("total_parts")
    private let colParentId   = Expression<String?>("parent_identifier")
    private let colArtworkURL = Expression<String?>("artwork_url")
    // nil = not yet probed, false = single-file, true = multi-file (book/album)
    private let colIsMultiPart = Expression<Bool?>("is_multi_part")

    // MARK: - Playback positions table
    private let positions    = Table("playback_positions")
    private let colChannelId = Expression<String>("channel_id")
    private let colTrackId   = Expression<String>("track_id")
    private let colPosSecs   = Expression<Double>("position_seconds")

    // MARK: - Playlists table
    private let playlists        = Table("playlists")
    private let colPlaylistId    = Expression<String>("id")
    private let colPlaylistName  = Expression<String>("name")
    private let colCreatedAt     = Expression<Double>("created_at")
    private let colUpdatedAt     = Expression<Double>("updated_at")
    private let colIsFavorites   = Expression<Bool>("is_favorites")
    private let colPlaylistOrder = Expression<Int?>("sort_order")

    // MARK: - Playlist tracks table
    private let playlistTracks   = Table("playlist_tracks")
    private let colPTId          = Expression<String>("id")
    private let colPTPlaylistId  = Expression<String>("playlist_id")
    private let colPTTrackId     = Expression<String>("track_id")
    private let colPTSortOrder   = Expression<Int>("sort_order")
    private let colPTAddedAt     = Expression<Double>("added_at")

    // MARK: - Track play history table
    private let playHistory      = Table("track_play_history")
    private let colPHChannelId   = Expression<String>("channel_id")
    private let colPHTrackId     = Expression<String>("track_id")
    private let colPHPlayedAt    = Expression<Double>("played_at")

    // MARK: - Bookmarks table (within-track timestamps)
    private let bookmarks         = Table("bookmarks")
    private let colBMId           = Expression<String>("id")
    private let colBMTrackId      = Expression<String>("track_id")
    private let colBMPositionSecs = Expression<Double>("position_seconds")
    private let colBMLabel        = Expression<String?>("label")
    private let colBMCreatedAt    = Expression<Double>("created_at")
    private let colBMIsAutosave   = Expression<Bool>("is_autosave")

    init(path: String? = nil) throws {
        if let path {
            db = try Connection(path)
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url  = docs.appendingPathComponent("parso_radio.sqlite")
            db = try Connection(url.path)
        }
        try createSchema()
    }

    private func createSchema() throws {
        try db.run(tracks.create(ifNotExists: true) { t in
            t.column(colId,          primaryKey: true)
            t.column(colSource)
            t.column(colTitle)
            t.column(colArtist)
            t.column(colDuration)
            t.column(colStreamURL)
            t.column(colDownURL)
            t.column(colLocalPath)
            t.column(colLicense)
            t.column(colTags)
            t.column(colQuality)
            t.column(colRawCreator)
            t.column(colComposer)
            t.column(colInstruments)
            t.column(colConfidence)
            t.column(colFetchedAt)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_composer ON tracks(composer)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_confidence ON tracks(metadata_confidence)")

        try db.run(positions.create(ifNotExists: true) { t in
            t.column(colChannelId, primaryKey: true)
            t.column(colTrackId)
            t.column(colPosSecs)
        })

        // Playlists table
        try db.run(playlists.create(ifNotExists: true) { t in
            t.column(colPlaylistId,   primaryKey: true)
            t.column(colPlaylistName)
            t.column(colCreatedAt)
            t.column(colUpdatedAt)
            t.column(colIsFavorites, defaultValue: false)
        })

        // Playlist tracks join table
        try db.run(playlistTracks.create(ifNotExists: true) { t in
            t.column(colPTId, primaryKey: true)
            t.column(colPTPlaylistId)
            t.column(colPTTrackId)
            t.column(colPTSortOrder)
            t.column(colPTAddedAt)
            t.unique(colPTPlaylistId, colPTTrackId)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_pt_playlist ON playlist_tracks(playlist_id, sort_order DESC)")

        // Track play history table
        try db.run(playHistory.create(ifNotExists: true) { t in
            t.column(colPHChannelId)
            t.column(colPHTrackId)
            t.column(colPHPlayedAt)
            t.primaryKey(colPHChannelId, colPHTrackId)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_ph_channel ON track_play_history(channel_id, played_at DESC)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_ph_played_at ON track_play_history(played_at DESC)")

        // Bookmarks: within-track timestamps, distinct from per-channel/playlist
        // positions. Many user bookmarks per track + one auto-save per track
        // (is_autosave=1, deterministic id `autosave:<trackId>`).
        try db.run(bookmarks.create(ifNotExists: true) { t in
            t.column(colBMId,           primaryKey: true)
            t.column(colBMTrackId)
            t.column(colBMPositionSecs)
            t.column(colBMLabel)
            t.column(colBMCreatedAt)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_bm_track ON bookmarks(track_id, position_seconds)")
        // Idempotent migration for the autosave flag — older DB rows default to 0.
        _ = try? db.run("ALTER TABLE bookmarks ADD COLUMN is_autosave INTEGER NOT NULL DEFAULT 0")

        // Idempotent column migrations — try? silently ignores duplicate-column errors
        _ = try? db.run("ALTER TABLE tracks ADD COLUMN added_date   REAL")
        _ = try? db.run("ALTER TABLE tracks ADD COLUMN is_local     INTEGER NOT NULL DEFAULT 0")
        _ = try? db.run("ALTER TABLE tracks ADD COLUMN part_number  INTEGER")
        _ = try? db.run("ALTER TABLE tracks ADD COLUMN total_parts  INTEGER")
        _ = try? db.run("ALTER TABLE tracks ADD COLUMN parent_identifier TEXT")
        _ = try? db.run("ALTER TABLE tracks ADD COLUMN artwork_url  TEXT")
        // NULL = not probed, 0 = single-file, 1 = multi-file (book/album)
        _ = try? db.run("ALTER TABLE tracks ADD COLUMN is_multi_part INTEGER")
        _ = try? db.run("CREATE INDEX IF NOT EXISTS idx_added_date ON tracks(added_date DESC)")
        _ = try? db.run("CREATE INDEX IF NOT EXISTS idx_parent_id ON tracks(parent_identifier)")

        // User-defined playlist ordering. Backfill legacy rows deterministically
        // by creation time so NULLs never sort ahead of explicitly-ordered ones.
        _ = try? db.run("ALTER TABLE playlists ADD COLUMN sort_order INTEGER")
        _ = try? db.run("""
            UPDATE playlists SET sort_order = (
                SELECT COUNT(*) FROM playlists p2
                WHERE p2.created_at <= playlists.created_at
            ) WHERE sort_order IS NULL
        """)

        // Enable FK enforcement
        _ = try? db.run("PRAGMA foreign_keys = ON")

        // Seed Favorites playlist if playlists table is empty
        if (try? db.scalar(playlists.count)) == 0 {
            let fav = Playlist.new(name: "Favorites", isFavorites: true)
            _ = try? db.run(playlists.insert(
                colPlaylistId   <- fav.id,
                colPlaylistName <- fav.name,
                colCreatedAt    <- fav.createdAt.timeIntervalSince1970,
                colUpdatedAt    <- fav.updatedAt.timeIntervalSince1970,
                colIsFavorites  <- true
            ))
        }
    }

    // MARK: - Track write

    func saveTracks(_ newTracks: [Track]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                for t in newTracks {
                    let insert = self.tracks.insert(or: .replace,
                        self.colId          <- t.id,
                        self.colSource      <- t.source,
                        self.colTitle       <- t.title,
                        self.colArtist      <- t.artist,
                        self.colDuration    <- t.duration,
                        self.colStreamURL   <- t.streamURL.absoluteString,
                        self.colDownURL     <- t.downloadURL?.absoluteString,
                        self.colLocalPath   <- t.localFilePath,
                        self.colLicense     <- t.license.rawValue,
                        self.colTags        <- Self.encode(t.tags),
                        self.colQuality     <- t.qualityScore,
                        self.colRawCreator  <- t.rawCreator,
                        self.colComposer    <- t.composer,
                        self.colInstruments <- Self.encode(t.instruments),
                        self.colConfidence  <- t.metadataConfidence,
                        self.colFetchedAt   <- Int64(Date().timeIntervalSince1970),
                        self.colAddedDate   <- t.addedDate?.timeIntervalSince1970,
                        self.colIsLocal     <- t.isLocal,
                        self.colPartNumber  <- t.partNumber,
                        self.colTotalParts  <- t.totalParts,
                        self.colParentId    <- t.parentIdentifier,
                        self.colArtworkURL  <- t.artworkURLString,
                        self.colIsMultiPart <- t.isMultiPart
                    )
                    _ = try? self.db.run(insert)
                }
                continuation.resume()
            }
        }
    }

    func markDownloaded(trackID: String, localPath: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let row = self.tracks.filter(self.colId == trackID)
                _ = try? self.db.run(row.update(self.colLocalPath <- localPath))
                continuation.resume()
            }
        }
    }

    // MARK: - Track read

    func fetchTracks(forChannel channel: Channel) async -> [Track] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                // Confidence threshold governs metadata quality:
                //   - Spoken-word / tag-only channels: 0.0 — all tracks are acceptable
                //   - Composer channels: 1.5 — filters misidentified tracks
                let threshold: Double
                if channel.contentType == .spokenWord || channel.composers.isEmpty {
                    threshold = 0.0
                } else {
                    threshold = 1.5
                }
                var query = self.tracks.filter(self.colConfidence >= threshold)
                if !channel.composers.isEmpty {
                    query = query.filter(channel.composers.contains(self.colComposer ?? ""))
                }
                if let src = channel.preferredSource {
                    query = query.filter(self.colSource == src)
                }
                query = query.order(self.colConfidence.desc, self.colQuality.desc)
                let result = (try? self.db.prepare(query))?
                    .compactMap(self.rowToTrack)
                    .filter { channel.matches($0) && SourceValidator.isValid($0, for: channel) } ?? []
                continuation.resume(returning: result)
            }
        }
    }

    func fetchTrack(id: String) async -> Track? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let row = (try? self.db.pluck(self.tracks.filter(self.colId == id)))
                continuation.resume(returning: row.flatMap(self.rowToTrack))
            }
        }
    }

    // All previously-expanded parts of a multi-file IA item, in part order.
    // Returns [] when the item has not been expanded in the DB yet — the
    // caller must then probe the network.
    func fetchTracks(forParentIdentifier parentId: String) async -> [Track] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let query = self.tracks
                    .filter(self.colParentId == parentId)
                    .order(self.colPartNumber.asc)
                let result = (try? self.db.prepare(query))?
                    .compactMap(self.rowToTrack) ?? []
                continuation.resume(returning: result)
            }
        }
    }

    // Drop every expanded part of a multi-file item. Used before re-probing
    // so stale mixed-format rows (from an older extraction) can't re-pollute
    // the single-format set via the DB-first path.
    func deleteTracks(forParentIdentifier parentId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? self.db.run(
                    self.tracks.filter(self.colParentId == parentId).delete())
                continuation.resume()
            }
        }
    }

    // Persist the multi-file probe verdict so a track only ever hits the
    // network once across all sessions. true→1, false→0, nil→NULL.
    func setIsMultiPart(_ value: Bool?, forTrackId id: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let row = self.tracks.filter(self.colId == id)
                _ = try? self.db.run(row.update(self.colIsMultiPart <- value))
                continuation.resume()
            }
        }
    }

    func fetchDownloadedTracks(forChannel channel: Channel) async -> [Track] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var query = self.tracks
                    .filter(self.colLocalPath != nil)
                    .filter(self.colConfidence >= 1.5)
                if !channel.composers.isEmpty {
                    query = query.filter(channel.composers.contains(self.colComposer ?? ""))
                }
                let result = (try? self.db.prepare(query))?
                    .compactMap(self.rowToTrack).filter { channel.matches($0) } ?? []
                continuation.resume(returning: result)
            }
        }
    }

    func evictOldTracks(olderThan days: Int = 30) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let cutoff = Int64(Date().timeIntervalSince1970) - Int64(days) * 86400
                // Only evict non-local, non-downloaded tracks
                let safeToDelete = self.tracks
                    .filter(self.colFetchedAt < cutoff)
                    .filter(self.colIsLocal == false)
                    .filter(self.colLocalPath == nil)
                _ = try? self.db.run(safeToDelete.delete())
                // Also clean up old play history
                let historyCutoff = Date().timeIntervalSince1970 - Double(days) * 86400
                _ = try? self.db.run(self.playHistory.filter(self.colPHPlayedAt < historyCutoff).delete())
                continuation.resume()
            }
        }
    }

    func trackCount() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let count = (try? self.db.scalar(self.tracks.count)) ?? 0
                continuation.resume(returning: count)
            }
        }
    }

    // MARK: - Playback position

    func savePosition(channelId: String, trackId: String, seconds: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let upsert = self.positions.insert(or: .replace,
                    self.colChannelId <- channelId,
                    self.colTrackId   <- trackId,
                    self.colPosSecs   <- seconds
                )
                _ = try? self.db.run(upsert)
                continuation.resume()
            }
        }
    }

    func loadPosition(channelId: String) async -> (trackId: String, seconds: Double)? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let row = try? self.db.pluck(self.positions.filter(self.colChannelId == channelId))
                if let row {
                    continuation.resume(returning: (row[self.colTrackId], row[self.colPosSecs]))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func clearPosition(channelId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? self.db.run(self.positions.filter(self.colChannelId == channelId).delete())
                continuation.resume()
            }
        }
    }

    // MARK: - Playlists

    func createPlaylist(name: String, isFavorites: Bool = false) async throws -> Playlist {
        let p = Playlist.new(name: name, isFavorites: isFavorites)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let maxOrder = (try? self.db.scalar(
                        self.playlists.select(self.colPlaylistOrder.max))) ?? 0
                    try self.db.run(self.playlists.insert(
                        self.colPlaylistId   <- p.id,
                        self.colPlaylistName <- p.name,
                        self.colCreatedAt    <- p.createdAt.timeIntervalSince1970,
                        self.colUpdatedAt    <- p.updatedAt.timeIntervalSince1970,
                        self.colIsFavorites  <- p.isFavorites,
                        self.colPlaylistOrder <- maxOrder + 1
                    ))
                    continuation.resume(returning: p)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetchPlaylists() async -> [Playlist] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let result = (try? self.db.prepare(
                    self.playlists.order(
                        self.colIsFavorites.desc,
                        self.colPlaylistOrder.asc,
                        self.colCreatedAt.asc
                    )
                ))?.compactMap { row -> Playlist? in
                    Playlist(
                        id:          row[self.colPlaylistId],
                        name:        row[self.colPlaylistName],
                        createdAt:   Date(timeIntervalSince1970: row[self.colCreatedAt]),
                        updatedAt:   Date(timeIntervalSince1970: row[self.colUpdatedAt]),
                        isFavorites: row[self.colIsFavorites]
                    )
                }
                continuation.resume(returning: result ?? [])
            }
        }
    }

    // Persist user-defined playlist order. `ids` is the desired order of the
    // NON-favorites playlists (Favorites stays pinned via isFavorites DESC).
    func setPlaylistOrder(_ ids: [String]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                try? self.db.transaction {
                    for (index, id) in ids.enumerated() {
                        let row = self.playlists.filter(self.colPlaylistId == id)
                        try self.db.run(row.update(self.colPlaylistOrder <- index))
                    }
                }
                continuation.resume()
            }
        }
    }

    func renamePlaylist(id: String, name: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let row = self.playlists.filter(self.colPlaylistId == id)
                _ = try? self.db.run(row.update(
                    self.colPlaylistName <- name,
                    self.colUpdatedAt    <- Date().timeIntervalSince1970
                ))
                continuation.resume()
            }
        }
    }

    func deletePlaylist(id: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                // Remove playlist_tracks first (FK cascade not guaranteed in all SQLite builds)
                _ = try? self.db.run(self.playlistTracks.filter(self.colPTPlaylistId == id).delete())
                _ = try? self.db.run(self.playlists.filter(self.colPlaylistId == id).delete())
                continuation.resume()
            }
        }
    }

    // MARK: - Playlist tracks

    func addTrack(_ track: Track, toPlaylist playlistId: String) async {
        // Save track first (insert or replace — idempotent)
        await saveTracks([track])
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let maxOrder = (try? self.db.scalar(
                    self.playlistTracks
                        .filter(self.colPTPlaylistId == playlistId)
                        .select(self.colPTSortOrder.max)
                )) ?? 0
                let pt = PlaylistTrack(
                    id:         UUID().uuidString,
                    playlistId: playlistId,
                    trackId:    track.id,
                    sortOrder:  maxOrder + 1,
                    addedAt:    Date()
                )
                // UNIQUE(playlist_id, track_id) — ignore if already present
                _ = try? self.db.run(self.playlistTracks.insert(or: .ignore,
                    self.colPTId         <- pt.id,
                    self.colPTPlaylistId <- pt.playlistId,
                    self.colPTTrackId    <- pt.trackId,
                    self.colPTSortOrder  <- pt.sortOrder,
                    self.colPTAddedAt    <- pt.addedAt.timeIntervalSince1970
                ))
                continuation.resume()
            }
        }
    }

    // Add an ORDERED set (a whole book/album) so it reads in the given order.
    // fetchTracks(forPlaylist:) sorts sort_order DESC, so the first element
    // must get the HIGHEST order to come back first.
    func addTracksOrdered(_ orderedTracks: [Track], toPlaylist playlistId: String) async {
        guard !orderedTracks.isEmpty else { return }
        await saveTracks(orderedTracks)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let maxOrder = (try? self.db.scalar(
                    self.playlistTracks
                        .filter(self.colPTPlaylistId == playlistId)
                        .select(self.colPTSortOrder.max)
                )) ?? 0
                let n = orderedTracks.count
                try? self.db.transaction {
                    for (i, track) in orderedTracks.enumerated() {
                        try self.db.run(self.playlistTracks.insert(or: .ignore,
                            self.colPTId         <- UUID().uuidString,
                            self.colPTPlaylistId <- playlistId,
                            self.colPTTrackId    <- track.id,
                            self.colPTSortOrder  <- maxOrder + (n - i),
                            self.colPTAddedAt    <- Date().timeIntervalSince1970
                        ))
                    }
                }
                continuation.resume()
            }
        }
    }

    func removeTrack(trackId: String, fromPlaylist playlistId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let row = self.playlistTracks
                    .filter(self.colPTPlaylistId == playlistId && self.colPTTrackId == trackId)
                _ = try? self.db.run(row.delete())
                continuation.resume()
            }
        }
    }

    func fetchTracks(forPlaylist playlistId: String) async -> [Track] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                // Fetch track IDs in sort_order DESC, then fetch each track individually
                let idQuery = """
                    SELECT pt.track_id FROM playlist_tracks pt
                    WHERE pt.playlist_id = ?
                    ORDER BY pt.sort_order DESC
                """
                let ids = (try? self.db.prepare(idQuery, playlistId))?
                    .compactMap { $0[0] as? String } ?? []
                let tracks = ids.compactMap { id -> Track? in
                    guard let row = try? self.db.pluck(self.tracks.filter(self.colId == id)) else { return nil }
                    return self.rowToTrack(row)
                }
                continuation.resume(returning: tracks)
            }
        }
    }

    func setTrackOrder(_ trackIds: [String], inPlaylist playlistId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                try? self.db.transaction {
                    for (index, trackId) in trackIds.enumerated() {
                        let row = self.playlistTracks
                            .filter(self.colPTPlaylistId == playlistId && self.colPTTrackId == trackId)
                        try self.db.run(row.update(self.colPTSortOrder <- index))
                    }
                }
                continuation.resume()
            }
        }
    }

    func isTrack(_ trackId: String, inPlaylist playlistId: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let count = (try? self.db.scalar(
                    self.playlistTracks
                        .filter(self.colPTPlaylistId == playlistId && self.colPTTrackId == trackId)
                        .count
                )) ?? 0
                continuation.resume(returning: count > 0)
            }
        }
    }

    // MARK: - Track play history

    func recordPlayed(channelId: String, trackId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? self.db.run(self.playHistory.insert(or: .replace,
                    self.colPHChannelId <- channelId,
                    self.colPHTrackId   <- trackId,
                    self.colPHPlayedAt  <- Date().timeIntervalSince1970
                ))
                continuation.resume()
            }
        }
    }

    func recentlyHeardIds(forChannel channelId: String, withinDays days: Int = 30) async -> Set<String> {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let cutoff = Date().timeIntervalSince1970 - Double(days) * 86400
                let ids = Set((try? self.db.prepare(
                    self.playHistory
                        .filter(self.colPHChannelId == channelId && self.colPHPlayedAt > cutoff)
                        .select(self.colPHTrackId)
                ))?.map { $0[self.colPHTrackId] } ?? [])
                continuation.resume(returning: ids)
            }
        }
    }

    /// User-initiated delete of every play-history row for `trackId`
    /// (removes it from the Recently Played list across every channel).
    func deletePlayHistory(trackId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? self.db.run(self.playHistory.filter(self.colPHTrackId == trackId).delete())
                continuation.resume()
            }
        }
    }

    /// "Clear All" on Recently Played — wipes the entire history table.
    func clearAllPlayHistory() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? self.db.run(self.playHistory.delete())
                continuation.resume()
            }
        }
    }

    func evictOldPlayHistory(olderThanDays days: Int = 30) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let cutoff = Date().timeIntervalSince1970 - Double(days) * 86400
                _ = try? self.db.run(self.playHistory.filter(self.colPHPlayedAt < cutoff).delete())
                continuation.resume()
            }
        }
    }

    func lastPlayedTrack(forChannel channelId: String) async -> Track? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let row = try? self.db.pluck(
                    self.playHistory
                        .filter(self.colPHChannelId == channelId)
                        .order(self.colPHPlayedAt.desc)
                        .limit(1)
                ) else { continuation.resume(returning: nil); return }
                let trackId = row[self.colPHTrackId]
                let track = (try? self.db.pluck(self.tracks.filter(self.colId == trackId)))
                    .flatMap(self.rowToTrack)
                continuation.resume(returning: track)
            }
        }
    }

    /// Newest plays first, deduped to one entry per track_id. Used by the
    /// "Recently Played" section in the main menu.
    func fetchRecentlyPlayedTracks(limit: Int = 30) async -> [Track] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                // playHistory has composite PK (channel_id, track_id), so the
                // same track played in two channels appears twice — dedupe by
                // taking MAX(played_at) per track_id.
                let sql = """
                    SELECT t.* FROM tracks t
                    INNER JOIN (
                        SELECT track_id, MAX(played_at) AS last_at
                        FROM track_play_history
                        GROUP BY track_id
                    ) ph ON ph.track_id = t.id
                    ORDER BY ph.last_at DESC
                    LIMIT ?
                """
                var out: [Track] = []
                if let rows = try? self.db.prepare(sql, limit) {
                    for r in rows {
                        // SQLite.swift Statement rows are arrays of bindings —
                        // round-trip through tracks.filter for type-safe decode.
                        if let id = r[0] as? String,
                           let row = try? self.db.pluck(self.tracks.filter(self.colId == id)),
                           let track = self.rowToTrack(row) {
                            out.append(track)
                        }
                    }
                }
                continuation.resume(returning: out)
            }
        }
    }

    // MARK: - Bookmarks

    func saveBookmark(_ bookmark: Bookmark) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? self.db.run(self.bookmarks.insert(or: .replace,
                    self.colBMId           <- bookmark.id,
                    self.colBMTrackId      <- bookmark.trackId,
                    self.colBMPositionSecs <- bookmark.positionSeconds,
                    self.colBMLabel        <- bookmark.label,
                    self.colBMCreatedAt    <- bookmark.createdAt.timeIntervalSince1970,
                    self.colBMIsAutosave   <- bookmark.isAutosave
                ))
                continuation.resume()
            }
        }
    }

    /// User-visible bookmarks only (excludes the autosave row).
    func fetchBookmarks(forTrack trackId: String) async -> [Bookmark] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var out: [Bookmark] = []
                let query = self.bookmarks
                    .filter(self.colBMTrackId == trackId && self.colBMIsAutosave == false)
                    .order(self.colBMPositionSecs.asc)
                if let rows = try? self.db.prepare(query) {
                    for row in rows {
                        out.append(self.rowToBookmark(row))
                    }
                }
                continuation.resume(returning: out)
            }
        }
    }

    func deleteBookmark(id: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? self.db.run(self.bookmarks.filter(self.colBMId == id).delete())
                continuation.resume()
            }
        }
    }

    func deleteAllBookmarks(forTrack trackId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? self.db.run(self.bookmarks.filter(self.colBMTrackId == trackId).delete())
                continuation.resume()
            }
        }
    }

    /// Insert-or-replace the single autosave bookmark for `trackId`.
    /// Deterministic id means we never accumulate stale autosaves.
    func saveAutosaveBookmark(trackId: String, positionSeconds: Double,
                              createdAt: Date = Date()) async {
        let bm = Bookmark.autosave(
            trackId: trackId,
            positionSeconds: positionSeconds,
            createdAt: createdAt
        )
        await saveBookmark(bm)
    }

    /// Returns the autosave bookmark for the track, if any. The autosave is
    /// what `playTrack` consults when it loads a track with no explicit seek
    /// offset, so the user resumes where they left off across app launches.
    func fetchAutosaveBookmark(forTrack trackId: String) async -> Bookmark? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bookmark?, Never>) in
            queue.async { [self] in
                let query = self.bookmarks
                    .filter(self.colBMTrackId == trackId && self.colBMIsAutosave == true)
                    .limit(1)
                if let row = try? self.db.pluck(query) {
                    continuation.resume(returning: self.rowToBookmark(row))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func deleteAutosaveBookmark(forTrack trackId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? self.db.run(self.bookmarks
                    .filter(self.colBMTrackId == trackId && self.colBMIsAutosave == true)
                    .delete())
                continuation.resume()
            }
        }
    }

    private func rowToBookmark(_ row: Row) -> Bookmark {
        Bookmark(
            id: row[self.colBMId],
            trackId: row[self.colBMTrackId],
            positionSeconds: row[self.colBMPositionSecs],
            label: row[self.colBMLabel],
            createdAt: Date(timeIntervalSince1970: row[self.colBMCreatedAt]),
            isAutosave: row[self.colBMIsAutosave]
        )
    }

    func offlineTrackCount(forChannel channel: Channel) async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var query = self.tracks.filter(self.colLocalPath != nil)
                if !channel.composers.isEmpty {
                    query = query.filter(channel.composers.contains(self.colComposer ?? ""))
                }
                if let src = channel.preferredSource {
                    query = query.filter(self.colSource == src)
                }
                let count = (try? self.db.scalar(query.count)) ?? 0
                continuation.resume(returning: count)
            }
        }
    }

    func offlineTrackCount(forPlaylist playlistId: String) async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let sql = """
                    SELECT COUNT(*) FROM tracks t
                    INNER JOIN playlist_tracks pt ON pt.track_id = t.id
                    WHERE pt.playlist_id = ? AND t.local_file_path IS NOT NULL
                """
                let count = (try? self.db.scalar(sql, playlistId) as? Int64).map(Int.init) ?? 0
                continuation.resume(returning: count)
            }
        }
    }

    // MARK: - Private

    private func rowToTrack(_ row: Row) -> Track? {
        guard let streamURL = URL(string: row[colStreamURL]) else { return nil }
        let addedDate: Date? = row[colAddedDate].map { Date(timeIntervalSince1970: $0) }
        return Track(
            id:                 row[colId],
            source:             row[colSource],
            title:              row[colTitle],
            artist:             row[colArtist],
            duration:           row[colDuration],
            streamURL:          streamURL,
            downloadURL:        row[colDownURL].flatMap(URL.init),
            localFilePath:      row[colLocalPath],
            license:            LicenseType(rawValue: row[colLicense]) ?? .rejected,
            tags:               Self.decode(row[colTags]),
            qualityScore:       row[colQuality],
            rawCreator:         row[colRawCreator],
            composer:           row[colComposer],
            instruments:        Self.decode(row[colInstruments]),
            metadataConfidence: row[colConfidence],
            addedDate:          addedDate,
            isLocal:            row[colIsLocal],
            partNumber:         row[colPartNumber],
            totalParts:         row[colTotalParts],
            parentIdentifier:   row[colParentId],
            artworkURLString:   row[colArtworkURL],
            isMultiPart:        row[colIsMultiPart]
        )
    }

    private static func encode(_ arr: [String]) -> String {
        (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
    }

    private static func decode(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }
}
