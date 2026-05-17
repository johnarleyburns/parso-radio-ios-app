import SwiftUI

struct MainMenuView: View {
    let onSelectChannel: (Channel) -> Void
    let dismissAll: () -> Void          // close the whole menu (back to player)

    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @Environment(\.dismiss) private var dismiss

    @State private var showSearch = false
    @State private var showAbout = false

    // Fixed section order (item 1). Alphabetical WITHIN each (item 9).
    private static let categoryOrder = [
        "Curated", "Ambient", "News", "Contemporary", "Audiobooks", "Lectures"
    ]

    static func orderedCategories() -> [String] {
        let present = Set(Channel.defaults.map(\.category))
        return categoryOrder.filter(present.contains)
    }

    private func channels(in category: String) -> [Channel] {
        Channel.defaults
            .filter { $0.category == category }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        // Push the playlist detail (play/shuffle/add/edit), not straight to playback.
        NavigationLink {
            PlaylistDetailView(playlist: playlist, dismissAll: dismissAll)
                .environmentObject(playlistVM)
                .environmentObject(playerVM)
                .environmentObject(offlineService)
        } label: {
            HStack {
                Label(playlist.name,
                      systemImage: playlist.isFavorites ? "heart.fill" : "music.note.list")
                Spacer()
                Text("\(playlistVM.trackCount(for: playlist))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showSearch = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .font(.body).padding(.vertical, 2)
                    }
                    .foregroundStyle(.primary)
                }

                // Persisted order (Favorites pinned first, then user order).
                let favorites = playlistVM.playlists.filter { $0.isFavorites }
                let others    = playlistVM.playlists.filter { !$0.isFavorites }
                if !playlistVM.playlists.isEmpty {
                    Section {
                        ForEach(favorites) { playlist in
                            playlistRow(playlist)
                        }
                        ForEach(others) { playlist in
                            playlistRow(playlist)
                        }
                        .onMove { indices, newOffset in
                            var reordered = others
                            reordered.move(fromOffsets: indices, toOffset: newOffset)
                            Task { await playlistVM.reorderPlaylists(reordered) }
                        }
                        .onDelete { indices in
                            let toDelete = indices.map { others[$0] }
                            Task {
                                for pl in toDelete { await playlistVM.deletePlaylist(pl) }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Playlists")
                            Spacer()
                            EditButton()
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }

                ForEach(Self.orderedCategories(), id: \.self) { category in
                    Section(category) {
                        ForEach(channels(in: category)) { channel in
                            Button {
                                onSelectChannel(channel)
                            } label: {
                                Label(channel.name, systemImage: channel.icon)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section {
                    Button {
                        showAbout = true
                    } label: {
                        Label("About", systemImage: "info.circle")
                            .font(.body).padding(.vertical, 2)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Parso Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Presented FROM the menu (not after dismissing it) so there is no
            // flash of the player screen between transitions (item 10).
            .sheet(isPresented: $showSearch) {
                SearchView(dismissAll: dismissAll)
                    .environmentObject(playlistVM)
                    .environmentObject(playerVM)
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
        }
    }
}
