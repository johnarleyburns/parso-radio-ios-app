import SwiftUI

// Additive-only playlist picker for an entire book/album. Separate from
// AddToPlaylistSheet (single-track toggle/remove) because adding a whole
// item is always additive — every part is appended, never toggled off.
struct AddItemToPlaylistSheet: View {
    let track: Track                       // triggering track; resolves the item
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var added = false
    @State private var newPlaylistName = ""
    @State private var showNewPlaylistField = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if isAdding {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Adding…")
                    }
                } else if added {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(playlistVM.playlists) { playlist in
                        Button(playlist.name) {
                            Task { await addToPlaylist(playlist) }
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
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await playlistVM.loadPlaylists() }
        }
    }

    private func commitNewPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Hide the input row + switch to the spinner BEFORE creating the
        // playlist, so the new list row never overlaps the filled field.
        newPlaylistName = ""
        showNewPlaylistField = false
        isAdding = true
        Task {
            let p = await playlistVM.createPlaylist(name: name)
            await addToPlaylist(p)
        }
    }

    private func addToPlaylist(_ playlist: Playlist) async {
        isAdding = true
        await playerVM.addEntireItemToPlaylist(from: track, to: playlist, using: playlistVM)
        await playlistVM.loadTracks(for: playlist)
        isAdding = false
        added = true
        try? await Task.sleep(nanoseconds: 800_000_000)
        dismiss()
    }
}
