import SwiftUI

struct AddToPlaylistSheet: View {
    let track: Track
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newPlaylistName = ""
    @State private var showNewPlaylistField = false
    @State private var inPlaylist: Set<String> = []
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(playlistVM.playlists) { playlist in
                    Button {
                        Task {
                            if inPlaylist.contains(playlist.id) {
                                await playlistVM.removeTrack(track, from: playlist)
                                inPlaylist.remove(playlist.id)
                            } else {
                                await playlistVM.addTrack(track, to: playlist)
                                inPlaylist.insert(playlist.id)
                            }
                        }
                    } label: {
                        HStack {
                            Text(playlist.name)
                            Spacer()
                            if inPlaylist.contains(playlist.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                if showNewPlaylistField {
                    HStack {
                        TextField("Playlist name", text: $newPlaylistName)
                            .focused($nameFocused)
                        Button("Add") { commitNewPlaylist() }
                            .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .onAppear { nameFocused = true }   // cursor ready immediately
                } else {
                    Button {
                        showNewPlaylistField = true
                    } label: {
                        Label("New Playlist…", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await playlistVM.loadPlaylists()
                for playlist in playlistVM.playlists {
                    if await playlistVM.isTrackInPlaylist(track, playlist: playlist) {
                        inPlaylist.insert(playlist.id)
                    }
                }
            }
        }
    }

    private func commitNewPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Tear down the input row BEFORE creating the playlist, so the new
        // row appearing in the list never overlaps the still-filled field
        // (the "name shown twice" flash).
        newPlaylistName = ""
        showNewPlaylistField = false
        Task {
            let p = await playlistVM.createPlaylist(name: name)
            await playlistVM.addTrack(track, to: p)
            inPlaylist.insert(p.id)
        }
    }
}
