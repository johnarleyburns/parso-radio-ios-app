import Foundation
import SQLite

// @unchecked Sendable: every database access is funnelled through the private
// serial `queue` below, so the otherwise non-Sendable SQLite `Connection` is
// only ever touched from one thread at a time. This is what lets the async
// wrappers capture `self` in their @Sendable continuation closures safely.
final class DatabaseService: @unchecked Sendable, DatabaseServiceProtocol {
    private let db: Connection
    private let queue = DispatchQueue(label: "guru.parso.db", qos: .utility)

    /// Shared instance using the default Documents/parso_radio.sqlite path.
    /// Fatal error if the database cannot be opened (required for app operation).
    static let shared: DatabaseService = {
        guard let service = try? DatabaseService() else {
            fatalError("Cannot open database at default path")
        }
        return service
    }()

    // MARK: - Tracks table
    private let tracks        = Table("tracks")
    private let colId         = Column<String>("id").expr
    private let colSource     = Column<String>("source").expr
    private let colTitle      = Column<String>("title").expr
    private let colArtist     = Column<String>("artist").expr
    private let colDuration   = Column<Double>("duration").expr
    private let colStreamURL  = Column<String>("stream_url").expr
    private let colDownURL    = Column<String?>("download_url").expr
    private let colLocalPath  = Column<String?>("local_file_path").expr
    private let colLicense    = Column<String>("license_type").expr
    private let colTags       = Column<String>("tags").expr
    private let colQuality    = Column<Double>("quality_score").expr
    private let colRawCreator = Column<String>("raw_creator").expr
    private let colComposer   = Column<String?>("composer").expr
    private let colInstruments = Column<String>("instruments").expr
    private let colConfidence = Column<Double>("metadata_confidence").expr
    private let colFetchedAt  = Column<Int64>("fetched_at").expr

    // Tracks — new columns
    private let colAddedDate  = Column<Double?>("added_date").expr
    private let colIsLocal    = Column<Bool>("is_local").expr
    private let colPartNumber = Column<Int?>("part_number").expr
    private let colTotalParts = Column<Int?>("total_parts").expr
    private let colParentId   = Column<String?>("parent_identifier").expr
    private let colArtworkURL = Column<String?>("artwork_url").expr
    // nil = not yet probed, false = single-file, true = multi-file (book/album)
    private let colIsMultiPart = Column<Bool?>("is_multi_part").expr

    // MARK: - Playback positions table
    private let positions    = Table("playback_positions")
    private let colChannelId = Column<String>("channel_id").expr
    private let colTrackId   = Column<String>("track_id").expr
    private let colPosSecs   = Column<Double>("position_seconds").expr

    // MARK: - Playlists table
    private let playlists        = Table("playlists")
    private let colPlaylistId    = Column<String>("id").expr
    private let colPlaylistName  = Column<String>("name").expr
    private let colCreatedAt     = Column<Double>("created_at").expr
    private let colUpdatedAt     = Column<Double>("updated_at").expr
    private let colIsFavorites   = Column<Bool>("is_favorites").expr
    private let colPlaylistOrder = Column<Int?>("sort_order").expr
    // Parental flag: parents mark playlists kid-safe; only those appear in Kids
    // Mode (and they're read-only there). Added via idempotent migration so
    // existing rows default to false.
    private let colPlaylistKidSafe = Column<Bool>("is_kid_safe").expr

    // MARK: - Playlist tracks table
    private let playlistTracks   = Table("playlist_tracks")
    private let colPTId          = Column<String>("id").expr
    private let colPTPlaylistId  = Column<String>("playlist_id").expr
    private let colPTTrackId     = Column<String>("track_id").expr
    private let colPTSortOrder   = Column<Int>("sort_order").expr
    private let colPTAddedAt     = Column<Double>("added_at").expr

    // MARK: - Track play history table
    private let playHistory      = Table("track_play_history")
    private let colPHChannelId   = Column<String>("channel_id").expr
    private let colPHTrackId     = Column<String>("track_id").expr
    private let colPHPlayedAt    = Column<Double>("played_at").expr

    // MARK: - Bookmarks table (within-track timestamps)
    private let bookmarks         = Table("bookmarks")
    private let colBMId           = Column<String>("id").expr
    private let colBMTrackId      = Column<String>("track_id").expr
    private let colBMPositionSecs = Column<Double>("position_seconds").expr
    private let colBMLabel        = Column<String?>("label").expr
    private let colBMCreatedAt    = Column<Double>("created_at").expr
    private let colBMIsAutosave   = Column<Bool>("is_autosave").expr

    // Curator Mode: per-(channel, track) verdict. status ∈ review/approved/
    // rejected. The approved set is a curated channel's play pool + what exports
    // to the bundled manifest; rejected is auto-excluded from future candidates.
    private let curation       = Table("curation")
    private let colCurChannel  = Column<String>("channel_id").expr
    private let colCurTrack    = Column<String>("track_id").expr
    private let colCurStatus   = Column<String>("status").expr
    private let colCurReviewedAt = Column<Double>("reviewed_at").expr
    private let colCurNote     = Column<String?>("note").expr

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
            t.column(colPlaylistKidSafe, defaultValue: false)
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

        // Curator Mode verdicts — one per (channel, track).
        try db.run(curation.create(ifNotExists: true) { t in
            t.column(colCurChannel)
            t.column(colCurTrack)
            t.column(colCurStatus)
            t.column(colCurReviewedAt)
            t.column(colCurNote)
            t.primaryKey(colCurChannel, colCurTrack)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_cur_channel_status ON curation(channel_id, status)")

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
        // Kids Mode: parental "kid safe" flag per playlist. Defaults to false
        // so EVERY existing playlist remains adult-by-default — parents must
        // explicitly opt-in per playlist.
        _ = try? db.run(
            "ALTER TABLE playlists ADD COLUMN is_kid_safe INTEGER NOT NULL DEFAULT 0")

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

    /// Remove tracks belonging to a registry channel (matched by its unique
    /// isolation stamp) that the current query no longer returns — i.e. stale
    /// results from a previous/broader query definition. Downloaded and
    /// imported-local tracks are preserved so offline playback keeps working.
    /// SAFE ONLY for registry channels: their `matches` is stamp-based and
    /// channel-unique, so this never deletes another channel's tracks.
    func pruneChannelTracks(forChannel channel: Channel, keeping freshIds: Set<String>) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let all = (try? self.db.prepare(self.tracks))?
                    .compactMap(self.rowToTrack) ?? []
                let stale = all.filter {
                    channel.matches($0)
                        && !freshIds.contains($0.id)
                        && $0.localFilePath == nil
                        && !$0.isLocal
                }
                let staleIds = stale.map(\.id)
                for t in stale {
                    _ = try? self.db.run(self.tracks.filter(self.colId == t.id).delete())
                }
                // Clean up orphaned curation rows for pruned tracks so
                // curationCounts and reviewSetTracks remain in sync.
                if !staleIds.isEmpty {
                    _ = try? self.db.run(
                        self.curation.filter(staleIds.contains(self.colCurTrack)).delete())
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
                // Collect evicted track IDs so we can clean up orphaned curation rows
                let evictedIds = (try? db.prepare(safeToDelete.select(colId)))?
                    .map { $0[colId] } ?? []
                _ = try? self.db.run(safeToDelete.delete())
                // Clean up orphaned curation rows that reference evicted tracks
                if !evictedIds.isEmpty {
                    _ = try? self.db.run(
                        self.curation.filter(evictedIds.contains(colCurTrack)).delete())
                }
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

    // MARK: - Curation (Curator Mode)

    /// Record a verdict for (channel, track). status ∈ "review"/"approved"/"rejected".
    func setCuration(channelId: String, trackId: String, status: String, note: String? = nil) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? db.run(curation.insert(or: .replace,
                    colCurChannel    <- channelId,
                    colCurTrack      <- trackId,
                    colCurStatus     <- status,
                    colCurReviewedAt <- Date().timeIntervalSince1970,
                    colCurNote       <- note))
                cont.resume()
            }
        }
    }

    func curationStatus(channelId: String, trackId: String) async -> String? {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                let row = try? db.pluck(curation.filter(colCurChannel == channelId && colCurTrack == trackId))
                cont.resume(returning: row?[colCurStatus])
            }
        }
    }

    /// Track ids with a given status for a channel.
    func curationTrackIds(channelId: String, status: String) async -> [String] {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                let q = curation.select(colCurTrack)
                    .filter(colCurChannel == channelId && colCurStatus == status)
                cont.resume(returning: (try? db.prepare(q))?.map { $0[colCurTrack] } ?? [])
            }
        }
    }

    /// (review, approved, rejected) counts for a channel.
    func curationCounts(channelId: String) async -> (review: Int, approved: Int, rejected: Int) {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                func n(_ s: String) -> Int {
                    (try? db.scalar(curation
                        .filter(colCurChannel == channelId && colCurStatus == s).count)) ?? 0
                }
                cont.resume(returning: (n("review"), n("approved"), n("rejected")))
            }
        }
    }

    /// Approved tracks for a channel, joined to full Track rows — a curated
    /// channel's play pool once it has a manifest.
    func fetchApprovedTracks(forChannelId channelId: String) async -> [Track] {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                let ids = (try? db.prepare(curation.select(colCurTrack)
                    .filter(colCurChannel == channelId && colCurStatus == "approved")))?
                    .map { $0[colCurTrack] } ?? []
                var out: [Track] = []
                for id in ids {
                    if let row = try? db.pluck(tracks.filter(colId == id)),
                       let t = rowToTrack(row) { out.append(t) }
                }
                cont.resume(returning: out)
            }
        }
    }

    /// Rejected tracks for a channel, joined to full Track rows.
    func fetchRejectedTracks(forChannelId channelId: String) async -> [Track] {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                let ids = (try? db.prepare(curation.select(colCurTrack)
                    .filter(colCurChannel == channelId && colCurStatus == "rejected")))?
                    .map { $0[colCurTrack] } ?? []
                var out: [Track] = []
                for id in ids {
                    if let row = try? db.pluck(tracks.filter(colId == id)),
                       let t = rowToTrack(row) { out.append(t) }
                }
                cont.resume(returning: out)
            }
        }
    }

    /// All channels → their approved tracks, for the JSON export.
    func exportApprovedByChannel() async -> [String: [Track]] {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                let pairs = (try? db.prepare(curation.filter(colCurStatus == "approved")))?
                    .map { ($0[colCurChannel], $0[colCurTrack]) } ?? []
                var out: [String: [Track]] = [:]
                for (ch, tid) in pairs {
                    if let row = try? db.pluck(tracks.filter(colId == tid)),
                       let t = rowToTrack(row) {
                        out[ch, default: []].append(t)
                    }
                }
                cont.resume(returning: out)
            }
        }
    }

    /// Insert `trackIds` into the channel's REVIEW queue, SKIPPING any that
    /// already carry a verdict (approved/rejected). Idempotent: re-ingesting
    /// candidates never resurrects rejected tracks (the reject set is sticky).
    func ensureReviewSet(channelId: String, trackIds: [String]) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let now = Date().timeIntervalSince1970
                for tid in trackIds {
                    let already = (try? db.scalar(curation
                        .filter(colCurChannel == channelId && colCurTrack == tid)
                        .count)) ?? 0
                    if already == 0 {
                        _ = try? db.run(curation.insert(
                            colCurChannel    <- channelId,
                            colCurTrack      <- tid,
                            colCurStatus     <- "review",
                            colCurReviewedAt <- now,
                            colCurNote       <- nil
                        ))
                    }
                }
                cont.resume()
            }
        }
    }

    /// Tracks currently in the review queue for a channel, joined to full
    /// track metadata (so the curator UI can render + audition them).
    func reviewSetTracks(channelId: String) async -> [Track] {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                let ids = (try? db.prepare(curation.select(colCurTrack)
                    .filter(colCurChannel == channelId && colCurStatus == "review")))?
                    .map { $0[colCurTrack] } ?? []
                var out: [Track] = []
                for id in ids {
                    if let row = try? db.pluck(tracks.filter(colId == id)),
                       let t = rowToTrack(row) { out.append(t) }
                }
                cont.resume(returning: out)
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
                        self.colPlaylistOrder <- maxOrder + 1,
                        self.colPlaylistKidSafe <- p.isKidSafe
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
                        isFavorites: row[self.colIsFavorites],
                        isKidSafe:   row[self.colPlaylistKidSafe]
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

    /// Parental "kid safe" flag — only kid-safe playlists appear in Kids Mode.
    func setPlaylistKidSafe(id: String, isKidSafe: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let row = self.playlists.filter(self.colPlaylistId == id)
                _ = try? self.db.run(row.update(
                    self.colPlaylistKidSafe <- isKidSafe,
                    self.colUpdatedAt       <- Date().timeIntervalSince1970
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

    /// Playlists that have at least one downloaded (offline-playable) track.
    /// Used to highlight which playlists work without a connection.
    func playlistIDsWithDownloads() async -> Set<String> {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let q = """
                    SELECT DISTINCT pt.playlist_id
                    FROM playlist_tracks pt
                    INNER JOIN tracks t ON t.id = pt.track_id
                    WHERE t.local_file_path IS NOT NULL
                """
                let ids = (try? self.db.prepare(q))?.compactMap { $0[0] as? String } ?? []
                continuation.resume(returning: Set(ids))
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
                // fetchTracks(forPlaylist:) reads ORDER BY sort_order DESC, so
                // the FIRST displayed track must get the HIGHEST sort_order.
                // Writing ascending here (sort_order = index) silently reversed
                // the playlist on every reorder — the critical bug this fixes.
                let n = trackIds.count
                try? self.db.transaction {
                    for (index, trackId) in trackIds.enumerated() {
                        let row = self.playlistTracks
                            .filter(self.colPTPlaylistId == playlistId && self.colPTTrackId == trackId)
                        try self.db.run(row.update(self.colPTSortOrder <- (n - index)))
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

    /// Nuke every row in every table (tracks, positions, playlists, playlist
    /// membership, play history, bookmarks). Used by Settings → "Clear All
    /// Data". Downloaded FILES are deleted separately by the caller.
    func wipeAllData() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                for table in [self.bookmarks, self.playHistory, self.playlistTracks,
                              self.playlists, self.positions, self.tracks, self.curation] {
                    _ = try? self.db.run(table.delete())
                }
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

    /// All-time play history (newest first, one entry per track) WITH the
    /// channel it was played in — so recommendations can split music vs
    /// audiobook listening by channel category.
    func fetchRecentlyPlayedWithChannel(limit: Int = 200) async -> [(track: Track, channelId: String)] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let sql = """
                    SELECT track_id, channel_id, MAX(played_at) AS last_at
                    FROM track_play_history
                    GROUP BY track_id
                    ORDER BY last_at DESC
                    LIMIT ?
                """
                var out: [(track: Track, channelId: String)] = []
                if let rows = try? self.db.prepare(sql, limit) {
                    for r in rows {
                        guard let tid = r[0] as? String, let cid = r[1] as? String,
                              let row = try? self.db.pluck(self.tracks.filter(self.colId == tid)),
                              let track = self.rowToTrack(row) else { continue }
                        out.append((track, cid))
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
