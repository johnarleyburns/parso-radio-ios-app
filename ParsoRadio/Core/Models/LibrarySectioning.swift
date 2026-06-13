import Foundation

struct LibrarySection: Identifiable {
    let id: MediaKind
    let label: String
    let icon: String
}

extension LibrarySection {
    static let ordered: [LibrarySection] = [
        .init(id: .music,    label: "Music",    icon: "music.note"),
        .init(id: .audiobook, label: "Books",    icon: "book"),
        .init(id: .podcast,   label: "Podcasts", icon: "newspaper"),
        .init(id: .lecture,   label: "Lectures", icon: "graduationcap"),
        .init(id: .ambient,   label: "Ambient",  icon: "leaf"),
    ]
}
