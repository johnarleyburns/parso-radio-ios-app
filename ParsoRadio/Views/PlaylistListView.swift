import SwiftUI

struct PlaylistListView: View {
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @Environment(\.dismiss) private var dismiss
    @State private var showCreateAlert = false
    @State private var newPlaylistName = ""
    @State private var playlistToRename: Playlist? = nil
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(playlistVM.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                            .environmentObject(playlistVM)
                            .environmentObject(playerVM)
                            .environmentObject(offlineService)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                if playlist.isFavorites {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                }
                                Text(playlist.name)
                                    .font(.body)
                            }
                            Text("\(playlistVM.trackCount(for: playlist)) tracks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !playlist.isFavorites {
                            Button(role: .destructive) {
                                Task { await playlistVM.deletePlaylist(playlist) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                playlistToRename = playlist
                                renameText = playlist.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New Playlist", isPresented: $showCreateAlert) {
                TextField("Name", text: $newPlaylistName)
                Button("Create") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        await playlistVM.createPlaylist(name: name)
                        newPlaylistName = ""
                    }
                }
                Button("Cancel", role: .cancel) { newPlaylistName = "" }
            }
            .alert("Rename Playlist", isPresented: Binding(
                get: { playlistToRename != nil },
                set: { if !$0 { playlistToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let p = playlistToRename {
                        Task {
                            await playlistVM.renamePlaylist(p, to: renameText)
                            playlistToRename = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) { playlistToRename = nil }
            }
            .task { await playlistVM.loadPlaylists() }
        }
    }
}
