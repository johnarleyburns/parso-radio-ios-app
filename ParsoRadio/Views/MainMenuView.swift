import SwiftUI

struct MainMenuView: View {
    let onSelectChannel: (Channel) -> Void
    let onPlayPlaylist: (Playlist) -> Void
    let onOpenSearch: () -> Void
    let onOpenAbout: () -> Void

    @EnvironmentObject var playlistVM: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onOpenSearch()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .font(.body).padding(.vertical, 2)
                    }
                    .foregroundStyle(.primary)
                }

                if !playlistVM.playlists.isEmpty {
                    Section("Playlists") {
                        ForEach(playlistVM.playlists) { playlist in
                            Button {
                                onPlayPlaylist(playlist)
                            } label: {
                                HStack {
                                    Label(playlist.name,
                                          systemImage: playlist.isFavorites ? "heart.fill" : "music.note.list")
                                    Spacer()
                                    Text("\(playlistVM.trackCount(for: playlist))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                ForEach(Channel.categories, id: \.self) { category in
                    Section(category) {
                        ForEach(Channel.defaults.filter { $0.category == category }) { channel in
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
                        onOpenAbout()
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
        }
    }
}
