import SwiftUI

struct AddToPlaylistSheet: View {
    let track: Track
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newPlaylistName = ""
    @State private var showNewPlaylistField = false
    @State private var inPlaylist: Set<String> = []

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
                        Button("Add") {
                            let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            Task {
                                let p = await playlistVM.createPlaylist(name: name)
                                await playlistVM.addTrack(track, to: p)
                                inPlaylist.insert(p.id)
                                newPlaylistName = ""
                                showNewPlaylistField = false
                            }
                        }
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
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
}
