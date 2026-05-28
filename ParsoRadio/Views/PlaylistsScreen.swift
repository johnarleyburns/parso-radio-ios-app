import SwiftUI

/// The Playlists library, reached by drilling in from the Main Menu. Each row
/// pushes the playlist detail; Edit reorders/deletes; + creates a new playlist.
struct PlaylistsScreen: View {
    let dismissAll: () -> Void
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @State private var editMode: EditMode = .inactive
    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        let favorites = playlistVM.playlists.filter { $0.isFavorites }
        let others    = playlistVM.playlists.filter { !$0.isFavorites }

        List {
            if playlistVM.playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Add tracks to a playlist from Track Info or search to get started.")
                )
            } else {
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
            HStack {
                Label(playlist.name,
                      systemImage: playlist.isFavorites ? "heart.fill" : "music.note.list")
                Spacer()
                if playlistVM.downloadedPlaylistIDs.contains(playlist.id) {
                    // Highlights that this playlist has downloads → plays offline.
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
                Text("\(playlistVM.trackCount(for: playlist))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.name), \(playlistVM.trackCount(for: playlist)) tracks"
            + (playlistVM.downloadedPlaylistIDs.contains(playlist.id) ? ", available offline" : ""))
        .accessibilityHint("Opens this playlist")
    }
}
