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
            Section {
                HStack(spacing: 12) {
                    // Play ALWAYS resumes if a saved spot exists (exact track +
                    // offset), otherwise plays from the top. The user scrubs
                    // manually if they don't like where it resumes.
                    Button {
                        Task {
                            await playerVM.resumePlaylist(playlist)
                            dismissAll?()
                        }
                    } label: {
                        Label(resume == nil ? "Play" : "Resume",
                              systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(resume == nil
                        ? "Plays this playlist from the beginning"
                        : "Resumes “\(resume!.track.title)” at \(clock(resume!.seconds))")

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
                    .accessibilityHint("Plays this playlist in shuffled order from the start")

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
                        .accessibilityLabel("Download playlist for offline")
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
                    trackDownloadControl(track)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Task {
                        await playerVM.loadPlaylist(playlist, startingAt: track)
                        dismissAll?()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Plays the playlist starting from this track")
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

    /// Trailing-edge per-track download UI. Three states: in-progress
    /// (spinner), downloaded (green checkmark, taps removes), not downloaded
    /// (arrow.down.circle button, taps starts a single-track download).
    @ViewBuilder
    private func trackDownloadControl(_ track: Track) -> some View {
        if offlineService.activeDownloads[track.id] != nil {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
                .accessibilityLabel("Downloading")
        } else if track.localFilePath != nil {
            Button {
                Task { await offlineService.removeOffline(track: track) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Downloaded — tap to remove")
        } else if track.downloadURL != nil {
            Button {
                Task { await offlineService.makeOffline(track: track) }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Download for offline")
        } else {
            // No downloadURL (e.g. stream-only source) — show nothing.
            EmptyView()
        }
    }
}
