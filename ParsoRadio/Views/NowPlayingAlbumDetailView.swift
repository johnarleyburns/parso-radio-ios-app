import SwiftUI

/// Shown when tapping the channel/album name on the Now Playing screen
/// for transient albums (live music, audiobooks) that don't have a Channel.
struct NowPlayingAlbumDetailView: View {
    let title: String
    let tracks: [Track]
    let parentIdentifier: String?

    @Environment(\.dismiss) private var dismiss

    private var thumbnailURL: URL? {
        guard let id = parentIdentifier ?? tracks.first?.id else { return nil }
        return URL(string: "https://archive.org/services/img/\(id)")
    }

    private var iaURL: URL? {
        guard let id = parentIdentifier else { return nil }
        return URL(string: "https://archive.org/details/\(id)")
    }

    private var formattedTotalDuration: String {
        tracks.reduce(0) { $0 + $1.duration }.formattedTime
    }

    private var isLibrivox: Bool {
        let haystack = (tracks.first?.tags.joined(separator: " ") ?? "").lowercased()
            + (tracks.first?.id ?? "").lowercased()
        return haystack.contains("librivox")
    }

    private var itemTypeName: String {
        isLibrivox ? "Book" : "Album"
    }

    private var trackLabel: String {
        isLibrivox ? "Chapters" : "Tracks"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let url = thumbnailURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                fallbackImage
                                    .resizable().scaledToFill()
                            }
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title3).fontWeight(.bold)
                        if !tracks.isEmpty {
                            Text("\(tracks.count) \(trackLabel.lowercased()) · \(formattedTotalDuration)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                }

                if !tracks.isEmpty {
                    Section(trackLabel) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.body).lineLimit(1)
                                    Text(track.duration.formattedTime)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let url = iaURL {
                    Section {
                        Link(destination: url) {
                            Label("View on Internet Archive", systemImage: "safari")
                        }
                    }
                }
            }
            .navigationTitle("\(itemTypeName) Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var fallbackImage: Image {
        let haystack = title.lowercased()
        // Try to match to an audiobook category image
        let mappings: [String: String] = [
            "science fiction": "lv-science-fiction", "fantasy": "lv-fantasy-mythology",
            "mystery": "lv-mystery-crime", "horror": "lv-horror-gothic",
            "romance": "lv-romance", "adventure": "lv-adventure",
            "history": "lv-history", "biography": "lv-biography",
            "philosophy": "lv-philosophy-mind", "science": "lv-science-nature",
            "religion": "lv-religion", "poetry": "lv-poetry",
            "drama": "lv-drama-plays", "short story": "lv-short-stories",
            "essay": "lv-essays-ideas", "war": "lv-war-military",
            "travel": "lv-travel", "literary": "lv-literary-fiction",
        ]
        for (keyword, imageName) in mappings {
            if haystack.contains(keyword), UIImage(named: imageName) != nil {
                return Image(imageName)
            }
        }
        if UIImage(named: "audiobooks") != nil { return Image("audiobooks") }
        return Image("playlists")
    }
}
