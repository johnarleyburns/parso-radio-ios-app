import SwiftUI

struct AudiobookDetailView: View {
    let entry: AudiobookEntry
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var showPlaylistPicker = false
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var isAdding = false

    private var iaURL: URL {
        URL(string: "https://archive.org/details/\(entry.id)")!
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AsyncImage(url: entry.thumbnailURL) { phase in
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.displayName)
                            .font(.title3).fontWeight(.bold)
                        Text(entry.author)
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let date = entry.formattedDate {
                            Text(date)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let desc = entry.description, !desc.isEmpty {
                            Text(desc.strippedHTML)
                                .font(.footnote).foregroundStyle(.secondary)
                                .lineLimit(6)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 8)
                }

                Section {
                    Link(destination: iaURL) {
                        Label("View on Internet Archive", systemImage: "safari")
                    }
                }

                if isLoading {
                    Section {
                        HStack { Spacer(); ProgressView("Loading chapters…"); Spacer() }
                    }
                } else if !tracks.isEmpty {
                    Section("Chapters (\(tracks.count))") {
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
                                Spacer(minLength: 8)
                                Button {
                                    Task { await playFrom(track); dismiss() }
                                } label: {
                                    Image(systemName: "play.circle")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Section {
                        Button {
                            showPlaylistPicker = true
                        } label: {
                            Label("Add to Playlist", systemImage: "plus.circle")
                        }
                        Button {
                            newPlaylistName = entry.displayName
                            showNewPlaylist = true
                        } label: {
                            Label("Add to New Playlist", systemImage: "folder.badge.plus")
                        }
                    }
                }
            }
            .navigationTitle("Audiobook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadTracks() }
            .confirmationDialog("Add to Playlist", isPresented: $showPlaylistPicker) {
                ForEach(playlistVM.playlists) { pl in
                    Button(pl.name) {
                        Task {
                            isAdding = true
                            await playlistVM.addTracks(tracks, to: pl)
                            await playlistVM.loadPlaylists()
                            isAdding = false
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New Playlist", isPresented: $showNewPlaylist) {
                TextField("Name", text: $newPlaylistName)
                Button("Create & Add") { Task { await createAndAdd() } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var fallbackImage: Image {
        if let cat = entry.categoryImageName {
            return Image(cat)
        }
        return Image("audiobooks")
    }

    private func loadTracks() async {
        guard let parts = await playerVM.resolveItemParts(identifier: entry.id) else {
            isLoading = false
            return
        }
        tracks = parts.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        isLoading = false
    }

    private func createAndAdd() async {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let pl = await playlistVM.createPlaylist(name: name)
        await playlistVM.addTracks(tracks, to: pl)
    }

    private func playFrom(_ track: Track) async {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let reordered = Array(tracks[idx...]) + Array(tracks[..<idx])
        await playerVM.playAlbumTracks(reordered, title: entry.displayName)
    }
}
