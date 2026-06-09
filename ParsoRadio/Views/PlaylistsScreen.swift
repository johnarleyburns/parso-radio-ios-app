import SwiftUI

/// The Playlists library, reached by drilling in from the Main Menu. Each row
/// pushes the playlist detail; Edit reorders/deletes; + creates a new playlist.
struct PlaylistsScreen: View {
    let dismissAll: () -> Void
    /// Loads + dismisses the menu when an auto-generated row (Music/Books for
    /// You) is tapped. Recently Played stays a navigation drill-in.
    let onSelectChannel: (Channel) -> Void

    @EnvironmentObject var playlistVM: PlaylistViewModel
    @State private var editMode: EditMode = .inactive
    @State private var showCreate = false
    @State private var newName = ""

    private var musicForYou: Channel? {
        Channel.defaults.first { $0.id == "music-for-you" }
    }
    private var booksForYou: Channel? {
        Channel.defaults.first { $0.id == "books-for-you" }
    }

    var body: some View {
        let favorites = playlistVM.playlists.filter { $0.isFavorites }
        let others    = playlistVM.playlists.filter { !$0.isFavorites }

        List {
            // Auto-generated entries live INSIDE Playlists so the top-level
            // menu stays focused on real channel categories. Recently Played
            // drills in to the existing screen; the For-You rows behave like
            // channels (load + dismiss).
            Section("Made for You") {
                NavigationLink(value: MenuRoute.recentlyPlayed) {
                    Label("Recently Played",
                          systemImage: "clock.arrow.circlepath")
                }
                if let m = musicForYou {
                    Button {
                        onSelectChannel(m)
                    } label: {
                        Label(m.name, systemImage: "sparkles")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityHint("Plays curated music recommendations based on your listening")
                }
                if let b = booksForYou {
                    Button {
                        onSelectChannel(b)
                    } label: {
                        Label(b.name, systemImage: "sparkles")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityHint("Plays book recommendations based on your listening")
                }
            }

            if playlistVM.playlists.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "music.note.list",
                        description: Text("Add tracks to a playlist from Track Info or search to get started.")
                    )
                }
            } else {
                Section("My Playlists") {
                    ForEach(favorites) { pl in row(pl) }
                    ForEach(others) { pl in row(pl) }
                        .onMove { indices, newOffset in
                            var reordered = others
                            reordered.move(fromOffsets: indices, toOffset: newOffset)
                            Task { await playlistVM.reorderPlaylists(reordered) }
                        }
                        .onDelete { indices in
                            let toDelete = indices.map { others[$0] }
                            Task { for pl in toDelete { await playlistVM.deletePlaylist(pl) } }
                        }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !playlistVM.playlists.isEmpty { EditButton() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Playlist")
            }
        }
        .alert("New Playlist", isPresented: $showCreate) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                newName = ""
                guard !name.isEmpty else { return }
                Task {
                    _ = await playlistVM.createPlaylist(name: name)
                    await playlistVM.loadPlaylists()
                }
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .task { await playlistVM.loadPlaylists() }
    }

    @ViewBuilder
    private func row(_ playlist: Playlist) -> some View {
        NavigationLink(value: MenuRoute.playlist(playlist)) {
            HStack(spacing: 12) {
                PlaylistRowThumbnail(playlistId: playlist.id)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if playlist.isFavorites {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                        Text(playlist.name)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if playlistVM.downloadedPlaylistIDs.contains(playlist.id) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Text("\(playlistVM.trackCount(for: playlist)) tracks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.name), \(playlistVM.trackCount(for: playlist)) tracks"
            + (playlistVM.downloadedPlaylistIDs.contains(playlist.id) ? ", available offline" : ""))
        .accessibilityHint("Opens this playlist")
    }
}

private struct PlaylistRowThumbnail: View {
    let playlistId: String
    @State private var image: UIImage?

    static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playlist-images")
    }

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("playlists")
                    .resizable()
                    .scaledToFill()
            }
        }
        .task {
            let url = Self.dir.appendingPathComponent("\(playlistId).png")
            if FileManager.default.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                image = img
            }
        }
    }
}
