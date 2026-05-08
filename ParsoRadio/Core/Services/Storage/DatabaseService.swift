import Foundation
import SQLite

final class DatabaseService {
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

    // MARK: - Playback positions table
    private let positions    = Table("playback_positions")
    private let colChannelId = Expression<String>("channel_id")
    private let colTrackId   = Expression<String>("track_id")
    private let colPosSecs   = Expression<Double>("position_seconds")

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
                        self.colFetchedAt   <- Int64(Date().timeIntervalSince1970)
                    )
                    try? self.db.run(insert)
                }
                continuation.resume()
            }
        }
    }

    func markDownloaded(trackID: String, localPath: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let row = self.tracks.filter(self.colId == trackID)
                try? self.db.run(row.update(self.colLocalPath <- localPath))
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
                //     (fetched with confidenceThreshold 0.0; no composer to validate against)
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
                query = query.order(self.colConfidence.desc, self.colQuality.desc)
                let rows = (try? self.db.prepare(query)) ?? AnySequence([])
                let result = rows.compactMap(self.rowToTrack).filter { channel.matches($0) }
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

    func fetchDownloadedTracks(forChannel channel: Channel) async -> [Track] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var query = self.tracks
                    .filter(self.colLocalPath != nil)
                    .filter(self.colConfidence >= 1.5)
                if !channel.composers.isEmpty {
                    query = query.filter(channel.composers.contains(self.colComposer ?? ""))
                }
                let rows = (try? self.db.prepare(query)) ?? AnySequence([])
                let result = rows.compactMap(self.rowToTrack).filter { channel.matches($0) }
                continuation.resume(returning: result)
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
                try? self.db.run(upsert)
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
                try? self.db.run(self.positions.filter(self.colChannelId == channelId).delete())
                continuation.resume()
            }
        }
    }

    // MARK: - Private

    private func rowToTrack(_ row: Row) -> Track? {
        guard let streamURL = URL(string: row[colStreamURL]) else { return nil }
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
            metadataConfidence: row[colConfidence]
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
