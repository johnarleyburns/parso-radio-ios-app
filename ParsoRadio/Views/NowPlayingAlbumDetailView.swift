import SwiftUI

/// Shown when tapping the channel/album name on the Now Playing screen
/// for transient albums (live music, audiobooks) that don't have a Channel.
struct NowPlayingAlbumDetailView: View {
    let title: String
    let tracks: [Track]
    let parentIdentifier: String?

    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    private var thumbnailURL: URL? {
        guard let id = parentIdentifier ?? tracks.first?.id else { return nil }
        return URL(string: "https://archive.org/services/img/\(id)")
    }

    private var iaURL: URL? {
        guard let id = parentIdentifier else { return nil }
        return URL(string: "https://archive.org/details/\(id)")
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
                                        .font(.body).lineLimit(3)
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
                            Label(isLibrivox ? "View book on archive.org" : "View Album on archive.org", systemImage: "safari")
                        }
                    }
                }
            }
            .navigationTitle(itemTypeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if playerVM.currentTrack != nil {
                albumMiniPlayer
            }
        }
    }

    @ViewBuilder
    private var albumMiniPlayer: some View {
        if let track = playerVM.currentTrack {
            HStack(spacing: 12) {
                ArtworkThumbnail(track: track, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline).fontWeight(.semibold).lineLimit(1)
                    Text(track.artist)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    playerVM.togglePlayPause()
                } label: {
                    Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(playerVM.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.thinMaterial)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(.separator), alignment: .top)
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
