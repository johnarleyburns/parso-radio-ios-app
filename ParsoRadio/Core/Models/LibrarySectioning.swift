import Foundation

struct LibrarySection: Identifiable {
    let id: MediaKind
    let label: String   // full — section headers & nav titles
    let short: String   // compact — Explore chips
    let icon: String
}

extension LibrarySection {
    static let ordered: [LibrarySection] = [
        .init(id: .music,     label: "Internet Archive Collections", short: "Music",    icon: "music.note"),
        .init(id: .audiobook, label: "Librivox Audiobooks",          short: "Books",    icon: "book"),
        .init(id: .lecture,   label: "Oxford Lectures",              short: "Lectures", icon: "graduationcap"),
        .init(id: .podcast,   label: "Open Podcasts",                short: "Podcasts", icon: "newspaper"),
        .init(id: .ambient,   label: "Ambient",                      short: "Ambient",  icon: "leaf"),
    ]

    static func section(for kind: MediaKind) -> LibrarySection {
        ordered.first { $0.id == kind } ?? ordered[0]
    }
}
