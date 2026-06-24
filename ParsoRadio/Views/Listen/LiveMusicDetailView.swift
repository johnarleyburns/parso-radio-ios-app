import SwiftUI

struct LiveMusicDetailView: View {
    let entry: LiveMusicEntry
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPlaylistPicker = false
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var isAdding = false
    @State private var useFallbackImage = false

    private var iaURL: URL {
        URL(string: "https://archive.org/details/\(entry.id)")!
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    albumArtwork

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
                            Text(desc)
                                .font(.footnote).foregroundStyle(.secondary)
                                .lineLimit(8)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 8)

                    Button {
                        Task {
                            await playAll()
                            dismiss()
                        }
                    } label: {
                        Label("Play All Tracks", systemImage: "play.fill")
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
                        HStack { Spacer(); ProgressView("Loading tracks\u{2026}"); Spacer() }
                    }
                } else if let errorMessage {
                    Section {
                        VStack(spacing: 12) {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task { await loadTracks() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                } else if tracks.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Text("No playable tracks found for this recording.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task { await loadTracks() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                } else {
                    Section("Tracks (\(tracks.count))") {
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
                                    Task {
                                        await playFrom(track)
                                        dismiss()
                                    }
                                } label: {
                                    Image(systemName: "play.circle")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Play \(track.title)")
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
            .navigationTitle("Live Recording")
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
                Button("Create & Add") {
                    Task { await createAndAdd() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var albumArtwork: some View {
        Group {
            if useFallbackImage {
                Image("live-music-default")
                    .resizable().scaledToFill()
            } else {
                AsyncImage(url: entry.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .task { await verifyImageSize() }
                    case .failure, .empty:
                        Image("live-music-default")
                            .resizable().scaledToFill()
                            .onAppear { useFallbackImage = true }
                    @unknown default:
                        Image("live-music-default")
                            .resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Album artwork for \(entry.displayName)")
    }

    private func verifyImageSize() async {
        guard let (data, _) = try? await URLSession.shared.data(from: entry.thumbnailURL),
              data.count < 2048
        else { return }
        useFallbackImage = true
    }

    private func loadTracks() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await InternetArchiveService().fetchTracksForIdentifier(entry.id)
            tracks = fetched.sorted { ($0.partNumber ?? 0) < ($1.partNumber ?? 0) }
        } catch {
            errorMessage = "Couldn't load tracks. Try again later."
        }
        isLoading = false
    }

    private func playAll() async {
        guard !tracks.isEmpty else { return }
        await playerVM.playAlbumTracks(tracks, title: entry.displayName)
    }

    private func playFrom(_ track: Track) async {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let reordered = Array(tracks[idx...]) + Array(tracks[..<idx])
        await playerVM.playAlbumTracks(reordered, title: entry.displayName)
    }

    private func createAndAdd() async {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let pl = await playlistVM.createPlaylist(name: name)
        await playlistVM.addTracks(tracks, to: pl)
    }
}
