import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    var dismissAll: (() -> Void)? = nil
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var offlineService: OfflineDownloadService
    @State private var editMode: EditMode = .inactive
    @ObservedObject private var kids = KidsModeController.shared
    // Where the user left off in THIS playlist (track still present + offset).
    @State private var resume: (track: Track, seconds: Double)? = nil

    var body: some View {
        List {
            // The nav title is the generic "Playlist"; the actual name reads
            // large here for legibility.
            Section {
                Text(playlist.name)
                    .font(.title2).fontWeight(.bold)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
            }

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
                            : "Resumes “\(resume!.track.title)” at \(resume!.seconds.formattedTime)")

                    Button {
                        Task {
                            await playerVM.shufflePlaylist(playlist)
                            dismissAll?()
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Plays this playlist in random order, starting on a random track")

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

            if !kids.isEnabled {
                Section {
                    NavigationLink {
                        AddTracksView(playlist: playlist, db: playlistVM.db)
                            .environmentObject(playlistVM)
                            .environmentObject(playerVM)
                    } label: {
                        Label("Add to Playlist…", systemImage: "plus.circle")
                    }
                }

                // Parental "Kid Safe" toggle. Only shown when NOT in Kids Mode
                // (parents configure this from regular mode). Available on EVERY
                // playlist including Favorites — parents may want to mark their
                // own curated Favorites playlist as kid-safe. (Audit decision.)
                Section {
                    Toggle(isOn: Binding(
                        get: { playlist.isKidSafe },
                        set: { newValue in
                            Task { await playlistVM.setKidSafe(playlist, newValue) }
                        }
                    )) {
                        Label("Kid Safe", systemImage: "figure.and.child.holdinghands")
                    }
                } footer: {
                    Text("When on, this playlist appears in Kids Mode (read-only — kids can play it but can't edit it).")
                }
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
                            Label("Last played · \((resume?.seconds ?? 0).formattedTime)",
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
        .navigationTitle("Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            if !kids.isEnabled {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .onChange(of: kids.isEnabled) { _, on in
            // Kids Mode flipped on while this view is open → kill the EditMode
            // session so no reorder/delete remains active.
            if on { editMode = .inactive }
        }
        .task {
            await playlistVM.loadTracks(for: playlist)
            resume = await playerVM.savedPlaylistResume(playlist)
        }
    }

    /// Trailing-edge per-track download UI. Three states: in-progress
    /// (spinner), downloaded (green checkmark, taps removes), not downloaded
    /// (arrow.down.circle button, taps starts a single-track download).
    @ViewBuilder
    private func trackDownloadControl(_ track: Track) -> some View {
        if let fraction = offlineService.trackProgress[track.id] {
            // Downloading: blue circular determinate ring with %.
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(fraction * 100))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 28, height: 28)
            .animation(.linear(duration: 0.2), value: fraction)
            .accessibilityLabel("Downloading \(Int(fraction * 100)) percent")
        } else if track.localFilePath != nil {
            Button {
                Task { await offlineService.removeOffline(track: track) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
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
