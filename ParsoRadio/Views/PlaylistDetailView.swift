import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    var dismissAll: (() -> Void)? = nil
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @State private var editMode: EditMode = .inactive
    // Where the user left off in THIS playlist (track still present + offset).
    @State private var resume: (track: Track, seconds: Double)? = nil

    var body: some View {
        List {
            if let r = resume {
                Section {
                    Button {
                        Task {
                            await playerVM.resumePlaylist(playlist)
                            dismissAll?()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Resume").font(.body).fontWeight(.semibold)
                                Text("“\(r.track.title)” · \(clock(r.seconds))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Picks up exactly where you stopped — including the offset within a chapter.")
                }
            }

            Section {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await playerVM.loadPlaylist(playlist)
                            dismissAll?()
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        playerVM.shuffleMode = true
                        Task {
                            await playerVM.loadPlaylist(playlist)
                            dismissAll?()
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if let progress = offlineService.activeDownloads[playlist.id] {
                        VStack(alignment: .trailing, spacing: 2) {
                            ProgressView(
                                value: Double(progress.completed),
                                total: Double(max(progress.total, 1))
                            )
                            .frame(width: 80)
                            Text("\(progress.completed)/\(progress.total)")
                                .font(.caption2)
                        }
                    } else {
                        Button {
                            Task { await offlineService.makeOffline(playlist: playlist) }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(playlistVM.currentPlaylistTracks) { track in
                HStack(spacing: 10) {
                    ArtworkThumbnail(track: track, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.body)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if track.id == resume?.track.id {
                            Label("Last played · \(clock(resume?.seconds ?? 0))",
                                  systemImage: "bookmark.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        } else if let date = track.displayDate {
                            Text(date.formatted(.dateTime.year().month().day()))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if track.localFilePath != nil {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Task {
                        await playerVM.loadPlaylist(playlist, startingAt: track)
                        dismissAll?()
                    }
                }
            }
            .onMove { indices, newOffset in
                var tracks = playlistVM.currentPlaylistTracks
                tracks.move(fromOffsets: indices, toOffset: newOffset)
                playlistVM.currentPlaylistTracks = tracks
                Task { await playlistVM.reorderTracks(tracks, inPlaylist: playlist) }
            }
            .onDelete { indices in
                let toRemove = indices.map { playlistVM.currentPlaylistTracks[$0] }
                Task {
                    for track in toRemove {
                        await playlistVM.removeTrack(track, from: playlist)
                    }
                    await playlistVM.loadTracks(for: playlist)
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    AddTracksView(playlist: playlist, db: playlistVM.db)
                        .environmentObject(playlistVM)
                        .environmentObject(playerVM)
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .task {
            await playlistVM.loadTracks(for: playlist)
            resume = await playerVM.savedPlaylistResume(playlist)
        }
    }

    private func clock(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}
