import Foundation
import SQLite

// @unchecked Sendable: every database access is funnelled through the private
// serial `queue` below, so the otherwise non-Sendable SQLite `Connection` is
// only ever touched from one thread at a time. This is what lets the async
// wrappers capture `self` in their @Sendable continuation closures safely.
final class DatabaseService: @unchecked Sendable {
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
    private let colPlaylistType  = Column<String>("playlist_type").expr
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

    // User-subscribed podcast feeds
    private let podcastSubs    = Table("podcast_subscriptions")
    private let colPSId        = Expression<String>("id")
    private let colPSName      = Expression<String>("name")
    private let colPSFeedURL   = Expression<String>("feed_url")
    private let colPSCreatedAt = Expression<Double>("created_at")
    private let colPSArtworkURL = Expression<String?>("artwork_url")

    // MARK: - Favorites table
    private let favorites       = Table("favorites")
    private let colFavId        = Column<String>("id").expr
    private let colFavKind      = Column<String>("kind").expr
    private let colFavDateAdded = Column<Double>("date_added").expr
    private let colFavTitle     = Column<String>("title").expr
    private let colFavCreator   = Column<String?>("creator").expr
    private let colFavArtwork   = Column<String?>("artwork_url").expr
    private let colFavSource    = Column<String>("source_identifier").expr
    private let colFavChapter   = Column<Int?>("resume_chapter").expr
    private let colFavPosition  = Column<Double?>("resume_position").expr
    private let colFavResumeAt  = Column<Double?>("resume_updated_at").expr

    // MARK: - Track metadata enrichment table
    private let trackMeta = Table("track_metadata")
    private let colTMTrackID = Expression<String>("track_id")
    private let colTMMBRecordingID = Expression<String?>("mb_recording_id")
    private let colTMMBWorkID = Expression<String?>("mb_work_id")
    private let colTMMBArtistID = Expression<String?>("mb_artist_id")
    private let colTMMBReleaseID = Expression<String?>("mb_release_id")
    private let colTMComposer = Expression<String?>("composer")
    private let colTMComposerMBID = Expression<String?>("composer_mbid")
    private let colTMPerformer = Expression<String?>("performer")
    private let colTMWorkTitle = Expression<String?>("work_title")
    private let colTMCatalogNumber = Expression<String?>("catalog_number")
    private let colTMGenreTags = Expression<String?>("genre_tags")
    private let colTMDurationMs = Expression<Int?>("duration_ms")
    private let colTMRecordingDate = Expression<String?>("recording_date")
    private let colTMComposerPortraitURL = Expression<String?>("composer_portrait_url")
    private let colTMAlbumArtURL = Expression<String?>("album_art_url")
    private let colTMTrackArtURL = Expression<String?>("track_art_url")
    private let colTMAuthor = Expression<String?>("author")
    private let colTMAuthorPortraitURL = Expression<String?>("author_portrait_url")
    private let colTMAuthorBio = Expression<String?>("author_bio")
    private let colTMAuthorBirthDate = Expression<String?>("author_birth_date")
    private let colTMAuthorDeathDate = Expression<String?>("author_death_date")
    private let colTMEnrichedAt = Expression<Double>("enriched_at")
    private let colTMEnrichmentSource = Expression<String?>("enrichment_source")

    // MARK: - Taste profile tables

    private let tasteProfileTerms = Table("taste_profile_terms")
    private let colTPTBucket = Column<String>("bucket").expr
    private let colTPTAxis   = Column<String>("axis").expr
    private let colTPTTerm   = Column<String>("term").expr
    private let colTPTWeight = Column<Double>("weight").expr
    private let colTPTLastTS = Column<Double>("last_ts").expr

    private let tasteSeen = Table("taste_seen_identifiers")
    private let colSeenIdentifier = Expression<String>("identifier")
    private let colSeenReason     = Expression<String>("reason")
    private let colSeenTS         = Expression<Double>("ts")

    private let recoSurfaced = Table("reco_surfaced")
    private let colRecoIdentifier = Expression<String>("identifier")
    private let colRecoTS         = Expression<Double>("ts")

    // MARK: - Book curated-for-you tables
    private let bookListenHistory = Table("book_listen_history")
    private let colBLHWorkKey   = Expression<String>("work_key")
    private let colBLHIdentifier = Expression<String>("identifier")
    private let colBLHTitle      = Expression<String?>("title")
    private let colBLHAuthor     = Expression<String?>("author")
    private let colBLHSubjects   = Expression<String?>("subjects")
    private let colBLHLastTS     = Expression<Double>("last_ts")

    private let bookCuratedHistory = Table("book_curated_history")
    private let colBCHWorkKey   = Expression<String>("work_key")
    private let colBCHIdentifier = Expression<String>("identifier")
    private let colBCHDay        = Expression<String>("day")
    private let colBCHTitle      = Expression<String?>("title")
    private let colBCHAuthor     = Expression<String?>("author")
    private let colBCHReason     = Expression<String?>("reason")
    private let colBCHTS         = Expression<Double>("ts")

    // MARK: - Made For You daily cache
    private let madeForYouDailyCache = Table("made_for_you_daily_cache")
    private let colMFYCDay      = Expression<String>("day")
    private let colMFYCPosition = Expression<Int>("position")
    private let colMFYCTrackId  = Expression<String>("track_id")
    private let colMFYCSource   = Expression<String>("source")
    private let colMFYCCreatedAt = Expression<Double>("created_at")

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

    private func columnExists(table: String, column: String) -> Bool {
        guard let rows = try? db.prepare("PRAGMA table_info(\(table))") else { return false }
        return rows.contains(where: { $0[1] as? String == column })
    }

    private func addColumnIfNotExists(table: String, column: String, definition: String) {
        guard !columnExists(table: table, column: column) else { return }
        _ = try? db.run("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
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
        addColumnIfNotExists(table: "bookmarks", column: "is_autosave", definition: "INTEGER NOT NULL DEFAULT 0")

        // User-subscribed podcast feeds
        try db.run(podcastSubs.create(ifNotExists: true) { t in
            t.column(colPSId,        primaryKey: true)
            t.column(colPSName)
            t.column(colPSFeedURL)
            t.column(colPSCreatedAt)
        })

        // Safe column migrations — checks PRAGMA table_info first
        addColumnIfNotExists(table: "tracks", column: "added_date",  definition: "REAL")
        addColumnIfNotExists(table: "tracks", column: "is_local",    definition: "INTEGER NOT NULL DEFAULT 0")
        addColumnIfNotExists(table: "tracks", column: "part_number", definition: "INTEGER")
        addColumnIfNotExists(table: "tracks", column: "total_parts", definition: "INTEGER")
        addColumnIfNotExists(table: "tracks", column: "parent_identifier", definition: "TEXT")
        addColumnIfNotExists(table: "tracks", column: "artwork_url", definition: "TEXT")
        addColumnIfNotExists(table: "tracks", column: "is_multi_part", definition: "INTEGER")
        _ = try? db.run("CREATE INDEX IF NOT EXISTS idx_added_date ON tracks(added_date DESC)")
        _ = try? db.run("CREATE INDEX IF NOT EXISTS idx_parent_id ON tracks(parent_identifier)")

        // User-defined playlist ordering. Backfill legacy rows deterministically
        // by creation time so NULLs never sort ahead of explicitly-ordered ones.
        addColumnIfNotExists(table: "playlists", column: "sort_order", definition: "INTEGER")
        _ = try? db.run("""
            UPDATE playlists SET sort_order = (
                SELECT COUNT(*) FROM playlists p2
                WHERE p2.created_at <= playlists.created_at
            ) WHERE sort_order IS NULL
        """)
        // Kids Mode: parental "kid safe" flag per playlist. Defaults to false
        // so EVERY existing playlist remains adult-by-default — parents must
        // explicitly opt-in per playlist.
        addColumnIfNotExists(table: "playlists", column: "is_kid_safe", definition: "INTEGER NOT NULL DEFAULT 0")
        addColumnIfNotExists(table: "playlists", column: "playlist_type", definition: "TEXT NOT NULL DEFAULT 'tracks'")
        addColumnIfNotExists(table: "podcast_subscriptions", column: "artwork_url", definition: "TEXT")

        // Track metadata enrichment (MusicBrainz, Wikidata, Cover Art Archive)
        try db.run(trackMeta.create(ifNotExists: true) { t in
            t.column(colTMTrackID, primaryKey: true)
            t.column(colTMMBRecordingID)
            t.column(colTMMBWorkID)
            t.column(colTMMBArtistID)
            t.column(colTMMBReleaseID)
            t.column(colTMComposer)
            t.column(colTMComposerMBID)
            t.column(colTMPerformer)
            t.column(colTMWorkTitle)
            t.column(colTMCatalogNumber)
            t.column(colTMGenreTags)
            t.column(colTMDurationMs)
            t.column(colTMRecordingDate)
            t.column(colTMComposerPortraitURL)
            t.column(colTMAlbumArtURL)
            t.column(colTMTrackArtURL)
            t.column(colTMAuthor)
            t.column(colTMAuthorPortraitURL)
            t.column(colTMAuthorBio)
            t.column(colTMAuthorBirthDate)
            t.column(colTMAuthorDeathDate)
            t.column(colTMEnrichedAt)
            t.column(colTMEnrichmentSource)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_track_meta_enriched ON track_metadata(enriched_at DESC)")

        // Favorites table (new universal favorites system)
        try db.run(favorites.create(ifNotExists: true) { t in
            t.column(colFavId, primaryKey: true)
            t.column(colFavKind)
            t.column(colFavDateAdded)
            t.column(colFavTitle)
            t.column(colFavCreator)
            t.column(colFavArtwork)
            t.column(colFavSource)
            t.column(colFavChapter)
            t.column(colFavPosition)
            t.column(colFavResumeAt)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_fav_kind ON favorites(kind, date_added DESC)")

        // Taste profile: decayed term weights per bucket/axis
        try db.run(tasteProfileTerms.create(ifNotExists: true) { t in
            t.column(colTPTBucket)
            t.column(colTPTAxis)
            t.column(colTPTTerm)
            t.column(colTPTWeight)
            t.column(colTPTLastTS)
            t.primaryKey(colTPTBucket, colTPTAxis, colTPTTerm)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_tpt_bucket ON taste_profile_terms(bucket, weight DESC)")

        // Durable exclusion set — survives track eviction
        try db.run(tasteSeen.create(ifNotExists: true) { t in
            t.column(colSeenIdentifier, primaryKey: true)
            t.column(colSeenReason)
            t.column(colSeenTS)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_seen_ts ON taste_seen_identifiers(ts DESC)")

        // Surfaced recommendation ring — cross-session freshness
        try db.run(recoSurfaced.create(ifNotExists: true) { t in
            t.column(colRecoIdentifier, primaryKey: true)
            t.column(colRecoTS)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_reco_ts ON reco_surfaced(ts DESC)")

        // Book listen history — durable record of every audiobook ever heard (work-level)
        try db.run(bookListenHistory.create(ifNotExists: true) { t in
            t.column(colBLHWorkKey, primaryKey: true)
            t.column(colBLHIdentifier)
            t.column(colBLHTitle)
            t.column(colBLHAuthor)
            t.column(colBLHSubjects)
            t.column(colBLHLastTS)
        })

        // Book curated history — permanent never-repeat ledger + per-day cache
        try db.run(bookCuratedHistory.create(ifNotExists: true) { t in
            t.column(colBCHWorkKey, primaryKey: true)
            t.column(colBCHIdentifier)
            t.column(colBCHDay)
            t.column(colBCHTitle)
            t.column(colBCHAuthor)
            t.column(colBCHReason)
            t.column(colBCHTS)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_book_curated_day ON book_curated_history(day)")

        // Made For You daily shelf cache
        try db.run(madeForYouDailyCache.create(ifNotExists: true) { t in
            t.column(colMFYCDay)
            t.column(colMFYCPosition)
            t.column(colMFYCTrackId)
            t.column(colMFYCSource)
            t.column(colMFYCCreatedAt)
            t.primaryKey(colMFYCDay, colMFYCPosition)
        })

        // Enable FK enforcement
        _ = try? db.run("PRAGMA foreign_keys = ON")

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

    func fetchAllDownloadedTracks(limit: Int = 100) async -> [Track] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let query = self.tracks
                    .filter(self.colLocalPath != nil)
                    .order(self.colFetchedAt.desc)
                    .limit(limit)
                let result = (try? self.db.prepare(query))?
                    .compactMap(self.rowToTrack) ?? []
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
                // Collect evicted track IDs for downstream cleanup.
                let evictedIds = (try? db.prepare(safeToDelete.select(colId)))?
                    .map { $0[colId] } ?? []
                _ = try? self.db.run(safeToDelete.delete())
                // Cascade-delete orphaned play_history rows for evicted tracks
                // so the INNER JOIN in fetchRecentlyPlayedTracks never returns empty.
                if !evictedIds.isEmpty {
                    _ = try? self.db.run(self.playHistory.filter(evictedIds.contains(self.colPHTrackId)).delete())
                }
                // Also clean up old play history (30-day window)
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

    func createPlaylist(name: String, isFavorites: Bool = false,
                        type: PlaylistType = .tracks) async throws -> Playlist {
        let p = Playlist.new(name: name, isFavorites: isFavorites, type: type)
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
                        self.colPlaylistType <- p.type.rawValue,
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
                        type:        PlaylistType(rawValue: row[self.colPlaylistType]) ?? .tracks,
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
                    WHERE t.local_file_path IS NOT NULL AND t.local_file_path != ''
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
                              self.playlists, self.positions, self.tracks,
                              self.tasteProfileTerms, self.tasteSeen, self.recoSurfaced] {
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

    // MARK: - Taste profile terms (decay-updated weights)

    func upsertTasteProfileTerm(bucket: String, axis: String, term: String,
                                 increment: Double, now: Double, tau: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if let row = try? db.pluck(
                    tasteProfileTerms.filter(colTPTBucket == bucket && colTPTAxis == axis && colTPTTerm == term)
                ) {
                    let prevWeight = row[colTPTWeight]
                    let prevTS = row[colTPTLastTS]
                    let dt = now - prevTS
                    let decayed = prevWeight * exp(-dt / tau)
                    let newWeight = decayed + increment
                    _ = try? db.run(tasteProfileTerms
                        .filter(colTPTBucket == bucket && colTPTAxis == axis && colTPTTerm == term)
                        .update(colTPTWeight <- newWeight, colTPTLastTS <- now))
                } else {
                    _ = try? db.run(tasteProfileTerms.insert(
                        colTPTBucket <- bucket,
                        colTPTAxis   <- axis,
                        colTPTTerm   <- term,
                        colTPTWeight <- increment,
                        colTPTLastTS <- now
                    ))
                }
                continuation.resume()
            }
        }
    }

    func fetchTasteProfileTerms(bucket: String?) async -> [(bucket: String, axis: String, term: String, weight: Double, lastTS: Double)] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var query = tasteProfileTerms
                if let b = bucket { query = query.filter(colTPTBucket == b) }
                let result = (try? db.prepare(query))?
                    .map { ($0[colTPTBucket], $0[colTPTAxis], $0[colTPTTerm], $0[colTPTWeight], $0[colTPTLastTS]) } ?? []
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Taste seen identifiers (durable exclusion)

    func upsertTasteSeenIdentifier(_ identifier: String, reason: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? db.run(tasteSeen.insert(or: .replace,
                    colSeenIdentifier <- identifier,
                    colSeenReason     <- reason,
                    colSeenTS         <- Date().timeIntervalSince1970
                ))
                continuation.resume()
            }
        }
    }

    func fetchTasteSeenIdentifiers() async -> Set<String> {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let ids = Set((try? db.prepare(tasteSeen.select(colSeenIdentifier)))?
                    .map { $0[colSeenIdentifier] } ?? [])
                continuation.resume(returning: ids)
            }
        }
    }

    // MARK: - Reco surfaced ring

    func pushRecoSurfaced(_ identifiers: [String], cap: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let now = Date().timeIntervalSince1970
                for id in identifiers {
                    _ = try? db.run(recoSurfaced.insert(or: .replace,
                        colRecoIdentifier <- id,
                        colRecoTS         <- now
                    ))
                }
                let rowCount = (try? db.scalar(recoSurfaced.count)) ?? 0
                if rowCount > cap {
                    let excess = rowCount - cap
                    _ = try? db.run(recoSurfaced
                        .order(colRecoTS.asc)
                        .limit(excess)
                        .delete())
                }
                continuation.resume()
            }
        }
    }

    func fetchRecoSurfacedIdentifiers() async -> Set<String> {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let ids = Set((try? db.prepare(recoSurfaced.select(colRecoIdentifier)))?
                    .map { $0[colRecoIdentifier] } ?? [])
                continuation.resume(returning: ids)
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

    // MARK: - Podcast subscriptions

    func fetchPodcastSubscriptions() async -> [PodcastSubscription] {
        await withCheckedContinuation { (cont: CheckedContinuation<[PodcastSubscription], Never>) in
            queue.async { [self] in
                let rows = (try? db.prepare(podcastSubs.order(colPSCreatedAt.desc)))
                var subs: [PodcastSubscription] = []
                if let rows {
                    for row in rows {
                        let s = PodcastSubscription(
                            id: row[colPSId],
                            name: row[colPSName],
                            feedURL: row[colPSFeedURL],
                            artworkURL: row[colPSArtworkURL],
                            createdAt: Date(timeIntervalSince1970: row[colPSCreatedAt])
                        )
                        subs.append(s)
                    }
                }
                cont.resume(returning: subs)
            }
        }
    }

    func savePodcastSubscription(_ sub: PodcastSubscription) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? db.run(podcastSubs.insert(or: .replace,
                    colPSId        <- sub.id,
                    colPSName      <- sub.name,
                    colPSFeedURL   <- sub.feedURL,
                    colPSCreatedAt <- sub.createdAt.timeIntervalSince1970,
                    colPSArtworkURL <- sub.artworkURL
                ))
                cont.resume()
            }
        }
    }

    func deletePodcastSubscription(_ sub: PodcastSubscription) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? db.run(podcastSubs.filter(colPSId == sub.id).delete())
                cont.resume()
            }
        }
    }

    // MARK: - Track metadata enrichment

    func saveTrackMetadata(_ meta: TrackMetadata) async {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                _ = try? db.run(trackMeta.insert(or: .replace,
                    colTMTrackID <- meta.trackID,
                    colTMMBRecordingID <- meta.mbRecordingID,
                    colTMMBWorkID <- meta.mbWorkID,
                    colTMMBArtistID <- meta.mbArtistID,
                    colTMMBReleaseID <- meta.mbReleaseID,
                    colTMComposer <- meta.composer,
                    colTMComposerMBID <- meta.composerMBID,
                    colTMPerformer <- meta.performer,
                    colTMWorkTitle <- meta.workTitle,
                    colTMCatalogNumber <- meta.catalogNumber,
                    colTMGenreTags <- (try? JSONEncoder().encode(meta.genreTags)).flatMap { String(data: $0, encoding: .utf8) },
                    colTMDurationMs <- meta.durationMs,
                    colTMRecordingDate <- meta.recordingDate,
                    colTMComposerPortraitURL <- meta.composerPortraitURL,
                    colTMAlbumArtURL <- meta.albumArtURL,
                    colTMTrackArtURL <- meta.trackArtURL,
                    colTMAuthor <- meta.author,
                    colTMAuthorPortraitURL <- meta.authorPortraitURL,
                    colTMAuthorBio <- meta.authorBio,
                    colTMAuthorBirthDate <- meta.authorBirthDate,
                    colTMAuthorDeathDate <- meta.authorDeathDate,
                    colTMEnrichedAt <- meta.enrichedAt,
                    colTMEnrichmentSource <- meta.enrichmentSource
                ))
                cont.resume()
            }
        }
    }

    func fetchTrackMetadata(trackID: String) async -> TrackMetadata? {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                guard let row = try? db.pluck(trackMeta.filter(colTMTrackID == trackID)) else {
                    cont.resume(returning: nil)
                    return
                }
                let genreTags: [String] = {
                    guard let data = row[colTMGenreTags]?.data(using: .utf8),
                          let tags = try? JSONDecoder().decode([String].self, from: data) else { return [] }
                    return tags
                }()
                cont.resume(returning: TrackMetadata(
                    trackID: row[colTMTrackID],
                    mbRecordingID: row[colTMMBRecordingID],
                    mbWorkID: row[colTMMBWorkID],
                    mbArtistID: row[colTMMBArtistID],
                    mbReleaseID: row[colTMMBReleaseID],
                    composer: row[colTMComposer],
                    composerMBID: row[colTMComposerMBID],
                    performer: row[colTMPerformer],
                    workTitle: row[colTMWorkTitle],
                    catalogNumber: row[colTMCatalogNumber],
                    genreTags: genreTags,
                    durationMs: row[colTMDurationMs],
                    recordingDate: row[colTMRecordingDate],
                    composerPortraitURL: row[colTMComposerPortraitURL],
                    albumArtURL: row[colTMAlbumArtURL],
                    trackArtURL: row[colTMTrackArtURL],
                    author: row[colTMAuthor],
                    authorPortraitURL: row[colTMAuthorPortraitURL],
                    authorBio: row[colTMAuthorBio],
                    authorBirthDate: row[colTMAuthorBirthDate],
                    authorDeathDate: row[colTMAuthorDeathDate],
                    enrichedAt: row[colTMEnrichedAt],
                    enrichmentSource: row[colTMEnrichmentSource]
                ))
            }
        }
    }

    // MARK: - Track decode

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

    /// Build a Track from a raw SQL result row (as [Binding?] from db.prepare).
    /// The offset shifts past any leading column.
    /// Column order:
    /// id(0), source(1), title(2), artist(3), duration(4), stream_url(5),
    /// download_url(6), local_file_path(7), license_type(8), tags(9),
    /// quality_score(10), raw_creator(11), composer(12), instruments(13),
    /// metadata_confidence(14), fetched_at(15), added_date(16), is_local(17),
    /// part_number(18), total_parts(19), parent_identifier(20),
    /// artwork_url(21), is_multi_part(22).
    private func rowToTrack(from row: Statement.Element, offset: Int) -> Track? {
        let o = offset
        guard let streamStr = row[o + 5] as? String,
              let streamURL = URL(string: streamStr) else { return nil }
        let addedDate: Double? = row[o + 16] as? Double
        return Track(
            id:                 (row[o + 0] as? String) ?? "",
            source:             (row[o + 1] as? String) ?? "",
            title:              (row[o + 2] as? String) ?? "",
            artist:             (row[o + 3] as? String) ?? "",
            duration:           (row[o + 4] as? Double) ?? 0,
            streamURL:          streamURL,
            downloadURL:        (row[o + 6] as? String).flatMap(URL.init),
            localFilePath:      row[o + 7] as? String,
            license:            LicenseType(rawValue: (row[o + 8] as? String) ?? "") ?? .rejected,
            tags:               Self.decode((row[o + 9] as? String) ?? "[]"),
            qualityScore:       (row[o + 10] as? Double) ?? 0,
            rawCreator:         (row[o + 11] as? String) ?? "",
            composer:           row[o + 12] as? String,
            instruments:        Self.decode((row[o + 13] as? String) ?? "[]"),
            metadataConfidence: (row[o + 14] as? Double) ?? 0,
            addedDate:          addedDate.map { Date(timeIntervalSince1970: $0) },
            isLocal:            (row[o + 17] as? Int64 ?? 0) != 0,
            partNumber:         row[o + 18] as? Int,
            totalParts:         row[o + 19] as? Int,
            parentIdentifier:   row[o + 20] as? String,
            artworkURLString:   row[o + 21] as? String,
            isMultiPart:        (row[o + 22] as? Int64).map { $0 != 0 }
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

    // MARK: - Favorites CRUD

    func fetchAllFavorites() async -> [Favorite] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let query = favorites.order(colFavDateAdded.desc)
                let result = (try? db.prepare(query))?
                    .compactMap(rowToFavorite) ?? []
                continuation.resume(returning: result)
            }
        }
    }

    func fetchFavorites(ofKind kind: FavoriteKind) async -> [Favorite] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let query = favorites
                    .filter(colFavKind == kind.rawValue)
                    .order(colFavDateAdded.desc)
                let result = (try? db.prepare(query))?
                    .compactMap(rowToFavorite) ?? []
                continuation.resume(returning: result)
            }
        }
    }

    func isFavorited(id: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let count = (try? db.scalar(
                    favorites.filter(colFavId == id).count)) ?? 0
                continuation.resume(returning: count > 0)
            }
        }
    }

    func fetchFavorite(id: String) async -> Favorite? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let row = try? db.pluck(favorites.filter(colFavId == id))
                continuation.resume(returning: row.flatMap(rowToFavorite))
            }
        }
    }

    func saveFavorite(_ fav: Favorite) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let insert = favorites.insert(or: .replace,
                    colFavId       <- fav.id,
                    colFavKind     <- fav.kind.rawValue,
                    colFavDateAdded <- fav.dateAdded.timeIntervalSince1970,
                    colFavTitle    <- fav.title,
                    colFavCreator  <- fav.creator,
                    colFavArtwork  <- fav.artworkURL?.absoluteString,
                    colFavSource   <- fav.sourceIdentifier,
                    colFavChapter  <- fav.resumePoint?.chapterIndex,
                    colFavPosition <- fav.resumePoint?.positionSeconds,
                    colFavResumeAt <- fav.resumePoint?.updatedAt.timeIntervalSince1970
                )
                _ = try? db.run(insert)
                continuation.resume()
            }
        }
    }

    func deleteFavorite(id: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? db.run(favorites.filter(colFavId == id).delete())
                continuation.resume()
            }
        }
    }

    func updateResumePoint(favoriteId: String, resumePoint: ResumePoint) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? db.run(favorites.filter(colFavId == favoriteId).update(
                    colFavChapter  <- resumePoint.chapterIndex,
                    colFavPosition <- resumePoint.positionSeconds,
                    colFavResumeAt <- resumePoint.updatedAt.timeIntervalSince1970
                ))
                continuation.resume()
            }
        }
    }

    func favoriteCount() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let c = (try? db.scalar(favorites.count)) ?? 0
                continuation.resume(returning: c)
            }
        }
    }

    func favoriteCount(ofKind kind: FavoriteKind) async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let c = (try? db.scalar(
                    favorites.filter(colFavKind == kind.rawValue).count)) ?? 0
                continuation.resume(returning: c)
            }
        }
    }



    // MARK: - Book curated-for-you

    func recordBookListened(workKey: String, identifier: String,
                            title: String? = nil, author: String? = nil,
                            subjects: String? = nil) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? db.run(bookListenHistory.insert(or: .replace,
                    colBLHWorkKey   <- workKey,
                    colBLHIdentifier <- identifier,
                    colBLHTitle      <- title,
                    colBLHAuthor     <- author,
                    colBLHSubjects   <- subjects,
                    colBLHLastTS     <- Date().timeIntervalSince1970
                ))
                continuation.resume()
            }
        }
    }

    func fetchBookListenedWorkKeys() async -> Set<String> {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let keys = Set((try? db.prepare(bookListenHistory.select(colBLHWorkKey)))?
                    .map { $0[colBLHWorkKey] } ?? [])
                continuation.resume(returning: keys)
            }
        }
    }

    func fetchBookCuratedWorkKeys() async -> Set<String> {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let keys = Set((try? db.prepare(bookCuratedHistory.select(colBCHWorkKey)))?
                    .map { $0[colBCHWorkKey] } ?? [])
                continuation.resume(returning: keys)
            }
        }
    }

    func fetchBookCuratedForDay(_ day: String) async -> BookForYouEntry? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let row = try? db.pluck(
                    bookCuratedHistory.filter(colBCHDay == day)
                ) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: rowToBookForYouEntry(row))
            }
        }
    }

    func insertBookCurated(_ entry: BookForYouEntry, day: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? db.run(bookCuratedHistory.insert(or: .replace,
                    colBCHWorkKey   <- entry.workKey,
                    colBCHIdentifier <- entry.identifier,
                    colBCHDay        <- day,
                    colBCHTitle      <- entry.title,
                    colBCHAuthor     <- entry.author,
                    colBCHReason     <- entry.reason,
                    colBCHTS         <- Date().timeIntervalSince1970
                ))
                continuation.resume()
            }
        }
    }

    func deleteBookCuratedForDay(_ day: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                _ = try? db.run(bookCuratedHistory.filter(colBCHDay == day).delete())
                continuation.resume()
            }
        }
    }

    func fetchLeastRecentlyCurated() async -> BookForYouEntry? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let row = try? db.pluck(
                    bookCuratedHistory.order(colBCHTS.asc)
                ) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: rowToBookForYouEntry(row))
            }
        }
    }


    private func rowToBookForYouEntry(_ row: Row) -> BookForYouEntry {
        BookForYouEntry(
            identifier: row[colBCHIdentifier],
            title: row[colBCHTitle] ?? "",
            author: row[colBCHAuthor] ?? "",
            subjects: [],
            reason: row[colBCHReason] ?? "",
            workKey: row[colBCHWorkKey]
        )
    }

    // MARK: - Taste backfill from play history

    func fetchRecentlyPlayedTracksForTasteBackfill(limit: Int = 200) async -> [Track] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
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

    // MARK: - Made For You daily cache

    func saveMadeForYouDailyCache(day: String, trackIds: [String], source: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let now = Date().timeIntervalSince1970
                for (idx, trackId) in trackIds.enumerated() {
                    _ = try? self.db.run(self.madeForYouDailyCache.insert(or: .replace,
                        self.colMFYCDay      <- day,
                        self.colMFYCPosition <- idx,
                        self.colMFYCTrackId  <- trackId,
                        self.colMFYCSource   <- source,
                        self.colMFYCCreatedAt <- now
                    ))
                }
                continuation.resume(returning: ())
            }
        }
    }

    struct MFYCCacheEntry {
        let trackId: String
        let source: String
        let position: Int
    }

    func fetchMadeForYouDailyCache(day: String) async -> [MFYCCacheEntry] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let query = self.madeForYouDailyCache
                    .filter(self.colMFYCDay == day)
                    .order(self.colMFYCPosition.asc)
                let entries: [MFYCCacheEntry] = (try? self.db.prepare(query))?.compactMap { row in
                    MFYCCacheEntry(
                        trackId: row[self.colMFYCTrackId],
                        source: row[self.colMFYCSource],
                        position: row[self.colMFYCPosition]
                    )
                } ?? []
                continuation.resume(returning: entries)
            }
        }
    }

    private func rowToFavorite(_ row: Row) -> Favorite? {
        guard let kind = FavoriteKind(rawValue: row[colFavKind]) else { return nil }
        let resumePoint: ResumePoint?
        if let pos = row[colFavPosition],
           let updated = row[colFavResumeAt] {
            resumePoint = ResumePoint(
                chapterIndex: row[colFavChapter],
                positionSeconds: pos,
                updatedAt: Date(timeIntervalSince1970: updated)
            )
        } else {
            resumePoint = nil
        }
        return Favorite(
            id: row[colFavId],
            kind: kind,
            dateAdded: Date(timeIntervalSince1970: row[colFavDateAdded]),
            title: row[colFavTitle],
            creator: row[colFavCreator],
            artworkURL: row[colFavArtwork].flatMap(URL.init),
            sourceIdentifier: row[colFavSource],
            resumePoint: resumePoint
        )
    }
}


