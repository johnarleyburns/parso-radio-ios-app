import Foundation

struct LibrarySection: Identifiable {
    let id: MediaKind
    let label: String
    let icon: String
}

extension LibrarySection {
    static let ordered: [LibrarySection] = [
        .init(id: .music,    label: "Curated Music",      icon: "music.note"),
        .init(id: .audiobook, label: "Librivox Audiobooks", icon: "book"),
        .init(id: .podcast,   label: "Open Podcasts",      icon: "newspaper"),
        .init(id: .lecture,   label: "Oxford Lectures",   icon: "graduationcap"),
        .init(id: .ambient,   label: "Ambient",           icon: "leaf"),
    ]
}
