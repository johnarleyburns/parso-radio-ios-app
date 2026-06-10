import SwiftUI

struct LiveMusicDetailView: View {
    let entry: LiveMusicEntry
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var loadingTask: Task<Void, Never>?
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
                            Image("concert\(String(format: "%02d", Int.random(in: 1...20)))")
                                .resizable().scaledToFill()
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.displayName)
                            .font(.title3).fontWeight(.bold)
                        if let location = entry.locationSummary {
                            Text(location)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let date = entry.formattedDate {
                            Text(date)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let desc = entry.description, !desc.isEmpty {
                            ExpandableText(text: desc.strippedHTML)
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
                        VStack(spacing: 12) {
                            ProgressView("Loading tracks…")
                            Button(role: .cancel) {
                                loadingTask?.cancel()
                                isLoading = false
                                loadError = nil
                            } label: {
                                Text("Cancel")
                                    .font(.subheadline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                } else if !tracks.isEmpty {
                    Section("Tracks (\(tracks.count))") {
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
                                Spacer(minLength: 8)
                                Button {
                                    Task {
                                        await playFrom(track)
                                        dismiss()
                                    }
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
                } else {
                    Section {
                        VStack(spacing: 12) {
                            if let error = loadError {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            } else {
                                Label("No tracks found for this item.", systemImage: "music.note.list")
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                loadError = nil
                                isLoading = true
                                Task { await loadTracks() }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Live Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                let t = Task { await loadTracks() }
                loadingTask = t
                await t.value
            }
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
                Button("Create & Add") {
                    Task { await createAndAdd() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func loadTracks() async {
        let identifier = entry.id
        let parts = await playerVM.resolveItemParts(identifier: identifier)
        if Task.isCancelled { return }
        guard let p = parts else {
            isLoading = false
            return
        }
        tracks = p.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
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
