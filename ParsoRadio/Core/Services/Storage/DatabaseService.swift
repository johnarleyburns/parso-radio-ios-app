import Foundation
import SQLite

final class DatabaseService {
    private let db: Connection
    private let queue = DispatchQueue(label: "guru.parso.db", qos: .utility)

    // Tracks table
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
    }

    // MARK: - Write

    func saveTracks(_ newTracks: [Track]) {
        queue.async { [weak self] in
            guard let self else { return }
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
        }
    }

    func markDownloaded(trackID: String, localPath: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let row = self.tracks.filter(self.colId == trackID)
            try? self.db.run(row.update(self.colLocalPath <- localPath))
        }
    }

    // MARK: - Read

    func fetchTracks(forChannel channel: Channel) -> [Track] {
        queue.sync {
            var query = tracks.filter(colConfidence >= 1.5)
            if let firstComposer = channel.composers.first, !channel.composers.isEmpty {
                query = query.filter(channel.composers.contains(colComposer ?? ""))
            }
            query = query.order(colConfidence.desc, colQuality.desc)
            let rows = (try? db.prepare(query)) ?? AnySequence([])
            return rows.compactMap(rowToTrack).filter { channel.matches($0) }
        }
    }

    func fetchDownloadedTracks(forChannel channel: Channel) -> [Track] {
        queue.sync {
            var query = tracks
                .filter(colLocalPath != nil)
                .filter(colConfidence >= 1.5)
            if !channel.composers.isEmpty {
                query = query.filter(channel.composers.contains(colComposer ?? ""))
            }
            let rows = (try? db.prepare(query)) ?? AnySequence([])
            return rows.compactMap(rowToTrack).filter { channel.matches($0) }
        }
    }

    func trackCount() -> Int {
        (try? db.scalar(tracks.count)) ?? 0
    }

    // MARK: - Helpers

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
