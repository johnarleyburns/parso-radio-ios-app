import SwiftUI

struct ItemDetailView: View {
    let identifier: String
    let title: String
    let creator: String
    let kind: SearchViewModel.ItemKind

    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var hasStartedPlayback = false

    private var itemNoun: String { kind == .book ? "Book" : "Album" }
    private var trackNoun: String { kind == .book ? "Chapter" : "Track" }
    private var tracksNoun: String { kind == .book ? "Chapters" : "Tracks" }

    private var artworkURL: URL? {
        URL(string: "https://archive.org/services/img/\(identifier)")
    }

    private var iaURL: URL {
        URL(string: "https://archive.org/details/\(identifier)")!
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    albumArtwork

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title3).fontWeight(.bold)
                        Text(creator)
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(itemNoun)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.top, 8)

                    Button {
                        Task {
                            await playAll()
                            dismiss()
                        }
                    } label: {
                        Label("Play Entire \(itemNoun)", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tracks.isEmpty)
                }

                Section {
                    Link(destination: iaURL) {
                        Label("View on Internet Archive", systemImage: "safari")
                    }
                }

                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading \(tracksNoun.lowercased())\u{2026}")
                            Spacer()
                        }
                    }
                } else if !tracks.isEmpty {
                    Section("\(tracksNoun) (\(tracks.count))") {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            let isCurrent = playerVM.currentTrack?.id == track.id
                            Button {
                                Task {
                                    await playFrom(track)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.body)
                                            .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                                            .lineLimit(2)
                                        if track.duration > 0 {
                                            Text(track.duration.formattedTime)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if isCurrent {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .foregroundStyle(.blue)
                                            .font(.caption)
                                    } else {
                                        Image(systemName: "play.circle")
                                            .font(.title3)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play \(track.title)")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadAndPlay() }
        }
    }

    @ViewBuilder
    private var albumArtwork: some View {
        if let url = artworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    fallbackArt
                @unknown default:
                    fallbackArt
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("\(itemNoun) artwork for \(title)")
        } else {
            fallbackArt
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var fallbackArt: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: kind == .book ? "book.closed.fill" : "opticaldisc.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    private func loadAndPlay() async {
        guard let parts = await playerVM.resolveItemParts(identifier: identifier) else {
            isLoading = false
            return
        }
        tracks = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        isLoading = false

        if !tracks.isEmpty, !hasStartedPlayback {
            hasStartedPlayback = true
            await playerVM.playAlbumTracks(tracks, title: title,
                                       mediaKind: kind == .book ? .audiobook : nil)
        }
    }

    private func playAll() async {
        guard !tracks.isEmpty else { return }
        await playerVM.playAlbumTracks(tracks, title: title,
                                       mediaKind: kind == .book ? .audiobook : nil)
    }

    private func playFrom(_ track: Track) async {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let reordered = Array(tracks[idx...]) + Array(tracks[..<idx])
        await playerVM.playAlbumTracks(reordered, title: title,
                                       mediaKind: kind == .book ? .audiobook : nil)
    }
}
