import Foundation

struct Channel: Codable, Identifiable {
    let id: String
    let name: String
    let composers: [String]
    let instruments: [String]
    let tags: [String]
    var isDownloaded: Bool

    func matches(_ track: Track) -> Bool {
        let composerMatch = composers.isEmpty || composers.contains(track.composer ?? "")
        let instrumentMatch = instruments.isEmpty
            || instruments.contains(where: { track.instruments.contains($0) })
        return composerMatch && instrumentMatch
    }
}

extension Channel {
    static let defaults: [Channel] = [
        Channel(
            id: "bach-vivaldi-strings",
            name: "Bach & Vivaldi — Strings",
            composers: ["bach", "vivaldi"],
            instruments: ["strings"],
            tags: ["classical", "baroque"],
            isDownloaded: false
        ),
        Channel(
            id: "chopin-rachmaninoff-piano",
            name: "Chopin & Rachmaninoff — Piano",
            composers: ["chopin", "rachmaninoff"],
            instruments: ["piano"],
            tags: ["classical", "romantic"],
            isDownloaded: false
        ),
        Channel(
            id: "classical",
            name: "Classical",
            composers: [],
            instruments: [],
            tags: ["classical"],
            isDownloaded: false
        ),
        Channel(
            id: "ambient",
            name: "Ambient",
            composers: [],
            instruments: [],
            tags: ["ambient"],
            isDownloaded: false
        ),
    ]
}
