import Foundation

struct LiveMusicCandidateFile {
    let name: String
    let format: String?
    let length: String?
    let title: String?
    let creator: String?

    init(name: String, format: String?, length: String? = nil, title: String? = nil, creator: String? = nil) {
        self.name = name
        self.format = format
        self.length = length
        self.title = title
        self.creator = creator
    }
}

enum LiveMusicValidationResult {
    case accepted(entry: LiveMusicEntry, tracks: [Track])
    case rejected(reason: String)
}

struct LiveMusicCandidateValidator {
    private let audioSelector = MP3AudioFormatSelector()

    func validate(
        identifier: String,
        expectedMMDD: String,
        title: String?,
        creator: String?,
        date: String?,
        venue: String? = nil,
        coverage: String? = nil,
        description: String? = nil,
        year: Int? = nil,
        downloads: Int = 0,
        files: [LiveMusicCandidateFile]
    ) -> LiveMusicValidationResult {

        let displayName: String
        if let title, !title.isEmpty {
            displayName = title
        } else if let creator, !creator.isEmpty {
            if let venue, !venue.isEmpty {
                displayName = "\(creator) at \(venue)"
            } else {
                displayName = creator
            }
        } else {
            return .rejected(reason: "No usable display name (missing title and creator)")
        }

        guard let date else { return .rejected(reason: "Missing recording date") }

        if !date.lowercased().contains(expectedMMDD.lowercased())
            && !date.lowercased().contains(expectedMMDD.replacingOccurrences(of: "-", with: "")) {
            let dateFormatters: [DateFormatter] = {
                let fmts = ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss"]
                return fmts.map { fmt in
                    let df = DateFormatter()
                    df.dateFormat = fmt
                    df.locale = Locale(identifier: "en_US_POSIX")
                    df.timeZone = TimeZone(identifier: "UTC")
                    return df
                }
            }()
            var dateMatches = false
            for df in dateFormatters {
                if let parsed = df.date(from: date) {
                    let mmdd = DateFormatter()
                    mmdd.dateFormat = "MM-dd"
                    if mmdd.string(from: parsed) == expectedMMDD {
                        dateMatches = true
                        break
                    }
                }
            }
            if !dateMatches {
                return .rejected(reason: "Recording date does not match today (\(expectedMMDD))")
            }
        }

        let playableFiles = files.filter { audioSelector.isAcceptedFormat($0.format) || audioSelector.isAcceptedFormatByExtension($0.name) }
        if playableFiles.isEmpty {
            return .rejected(reason: "No playable MP3 audio files found (requires MP3)")
        }

        let entry = LiveMusicEntry(
            id: identifier,
            creator: creator ?? "Unknown Artist",
            title: title,
            venue: venue,
            coverage: coverage,
            date: date,
            year: year,
            downloads: downloads,
            dateString: expectedMMDD,
            description: description
        )

        let tracks = playableFiles.enumerated().compactMap { index, file -> Track? in
            let enc = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.name
            let encodedId = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
            guard let streamURL = URL(string: "https://archive.org/download/\(encodedId)/\(enc)") else { return nil }
            let isMulti = playableFiles.count > 1
            return Track(
                id: "\(identifier)/\(file.name)",
                source: "internet_archive",
                title: file.title ?? (isMulti ? file.name : (title ?? identifier)),
                artist: file.creator ?? creator ?? "Unknown",
                duration: LiveMusicCandidateValidator.parseRuntime(file.length),
                streamURL: streamURL,
                downloadURL: streamURL,
                localFilePath: nil,
                license: .publicDomain,
                tags: [],
                qualityScore: 0.7,
                rawCreator: file.creator ?? creator ?? "",
                composer: nil,
                instruments: [],
                metadataConfidence: 1.0,
                addedDate: nil,
                partNumber: isMulti ? index + 1 : nil,
                totalParts: isMulti ? playableFiles.count : nil,
                parentIdentifier: isMulti ? identifier : nil,
                isMultiPart: isMulti ? true : false
            )
        }

        return .accepted(entry: entry, tracks: tracks)
    }

    static func parseRuntime(_ raw: String?) -> Double {
        guard let s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return 0 }
        if let d = Double(s) { return d }
        let parts = s.split(separator: ":").compactMap { Double($0) }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return 0
    }
}
