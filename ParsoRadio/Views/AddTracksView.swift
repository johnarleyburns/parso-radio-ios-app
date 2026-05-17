import SwiftUI
import UniformTypeIdentifiers

struct AddTracksView: View {
    let playlist: Playlist
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var showFolderPicker = false
    @State private var showSearch = false
    @State private var isImporting = false
    @State private var importProgress: String = ""

    private let importService: LocalFileImportService

    init(playlist: Playlist, db: DatabaseService) {
        self.playlist = playlist
        self.importService = LocalFileImportService(db: db)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import from Files…", systemImage: "doc.badge.plus")
                    }
                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("Import Folder…", systemImage: "folder.badge.plus")
                    }
                }
                Section {
                    Button {
                        showSearch = true
                    } label: {
                        Label("Search (IA / Librivox)", systemImage: "magnifyingglass")
                    }
                }
                if isImporting {
                    Section {
                        HStack {
                            ProgressView()
                            Text(importProgress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPickerView(
                    allowedTypes: [.mp3, .mpeg4Audio, .aiff, .wav],
                    allowsMultipleSelection: true
                ) { urls in
                    importFiles(urls)
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                DocumentPickerView(
                    allowedTypes: [.folder],
                    allowsMultipleSelection: false,
                    asCopy: false
                ) { urls in
                    if let folder = urls.first {
                        importFolder(folder)
                    }
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchView()
                    .environmentObject(playlistVM)
                    .environmentObject(playerVM)
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        isImporting = true
        Task {
            for (i, url) in urls.enumerated() {
                importProgress = "Importing \(i + 1) of \(urls.count)…"
                _ = try? await importService.importFile(at: url, intoPlaylist: playlist)
            }
            await playlistVM.loadTracks(for: playlist)
            isImporting = false
            dismiss()
        }
    }

    private func importFolder(_ url: URL) {
        isImporting = true
        importProgress = "Scanning folder…"
        Task {
            _ = try? await importService.importFolder(at: url, intoPlaylist: playlist)
            await playlistVM.loadTracks(for: playlist)
            isImporting = false
            dismiss()
        }
    }
}
