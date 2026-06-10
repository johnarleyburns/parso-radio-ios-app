import SwiftUI
import PhotosUI

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
    @State private var showImagePicker = false
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var customImage: UIImage?

    static var playlistImagesDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playlist-images")
    }

    var body: some View {
        List {
            Section {
                Text(playlist.name)
                    .font(.title2).fontWeight(.bold)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)

                // Playlist image — square, full width minus margin
                playlistHeaderImage
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottomTrailing) {
                        Menu {
                            Button {
                                showImagePicker = true
                            } label: {
                                Label("Choose Photo", systemImage: "photo")
                            }
                            if customImage != nil {
                                Button(role: .destructive) {
                                    removePlaylistImage()
                                } label: {
                                    Label("Remove Image", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "camera.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                        }
                        .padding(8)
                    }
            }

            Section {
                HStack(spacing: 24) {
                    Button {
                        Task {
                            await playerVM.resumePlaylist(playlist)
                            dismissAll?()
                        }
                    } label: {
                        Image(systemName: resume == nil ? "play.fill" : "play.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(resume == nil ? "Play" : "Resume")
                    .accessibilityHint(resume == nil
                        ? "Plays this playlist from the beginning"
                            : "Resumes \(resume!.track.title) at \(resume!.seconds.formattedTime)")

                    Button {
                        Task {
                            await playerVM.shufflePlaylist(playlist)
                            dismissAll?()
                        }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Shuffle")
                    .accessibilityHint("Plays this playlist in random order")

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

                    if playlistVM.downloadedPlaylistIDs.contains(playlist.id) {
                        Button {
                            Task {
                                await offlineService.removeOffline(playlist: playlist)
                                await playlistVM.loadPlaylists()
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .accessibilityLabel("Remove downloaded tracks for this playlist")
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
        .onChange(of: offlineService.singleTrackVersion) { _, _ in
            Task { await playlistVM.loadTracks(for: playlist) }
        }
        .task {
            await playlistVM.loadTracks(for: playlist)
            resume = await playerVM.savedPlaylistResume(playlist)
            loadCustomImage()
        }
        .photosPicker(isPresented: $showImagePicker, selection: $selectedImageItem,
                       matching: .images)
        .onChange(of: selectedImageItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    savePlaylistImage(data)
                }
            }
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

    @ViewBuilder
    private var playlistHeaderImage: some View {
        if let customImage {
            Image(uiImage: customImage)
                .resizable()
                .scaledToFill()
        } else if !playlistVM.currentPlaylistTracks.isEmpty,
                  let firstTrack = playlistVM.currentPlaylistTracks.first {
            ArtworkThumbnail(track: firstTrack, size: UIScreen.main.bounds.width - 40)
        } else {
            Image("playlists")
                .resizable()
                .scaledToFit()
        }
    }

    private func loadCustomImage() {
        let url = Self.playlistImagesDir.appendingPathComponent("\(playlist.id).png")
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            customImage = img.squareScaled(to: CGSize(width: 600, height: 600))
        }
    }

    private func savePlaylistImage(_ data: Data) {
        try? FileManager.default.createDirectory(at: Self.playlistImagesDir,
                                                  withIntermediateDirectories: true)
        let url = Self.playlistImagesDir.appendingPathComponent("\(playlist.id).png")
        try? data.write(to: url, options: .atomic)
        if let img = UIImage(data: data) {
            customImage = img.squareScaled(to: CGSize(width: 600, height: 600))
        }
    }

    private func removePlaylistImage() {
        let url = Self.playlistImagesDir.appendingPathComponent("\(playlist.id).png")
        try? FileManager.default.removeItem(at: url)
        customImage = nil
    }
}
