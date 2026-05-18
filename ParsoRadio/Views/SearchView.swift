import SwiftUI

struct SearchView: View {
    var dismissAll: (() -> Void)? = nil
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @StateObject private var searchVM: SearchViewModel
    @State private var showAddToPlaylist: Track? = nil
    @State private var showAddItemToPlaylist: SearchViewModel.ResultGroup? = nil
    @State private var selectedResult: SearchViewModel.ResultGroup? = nil
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(dismissAll: (() -> Void)? = nil,
         archiveService: InternetArchiveService = InternetArchiveService()) {
        self.dismissAll = dismissAll
        _searchVM = StateObject(wrappedValue: SearchViewModel(
            archiveService: archiveService
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search music, audiobooks…", text: $searchVM.query)
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onChange(of: searchVM.query) { _ in searchVM.searchChanged() }
                    if !searchVM.query.isEmpty {
                        Button { searchVM.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.vertical, 8)

                if searchVM.query.count < 2 {
                    historyList
                } else {
                    if searchVM.isSearching { ProgressView().padding() }
                    if let error = searchVM.errorMessage {
                        ContentUnavailableView("Search failed", systemImage: "wifi.slash",
                                                description: Text(error))
                    } else if searchVM.showNoResults {
                        ContentUnavailableView.search(text: searchVM.query)
                    }
                    resultsList
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $showAddToPlaylist) { track in
                AddToPlaylistSheet(track: track)
                    .environmentObject(playlistVM)
            }
            .sheet(item: $showAddItemToPlaylist) { group in
                AddItemToPlaylistSheet(track: searchTrack(group))
                    .environmentObject(playlistVM)
                    .environmentObject(playerVM)
            }
            .confirmationDialog(
                selectedResult?.title ?? "",
                isPresented: Binding(
                    get: { selectedResult != nil },
                    set: { if !$0 { selectedResult = nil } }
                ),
                titleVisibility: .visible,
                presenting: selectedResult
            ) { group in
                Button("Play") {
                    Task { await playerVM.playSearchResult(group); dismissAll?() }
                }
                Button("Add to Playlist") { showAddToPlaylist = searchTrack(group) }
                if let kind = searchVM.itemKinds[group.id], kind != .track {
                    let label = kind == .book ? "Book" : "Album"
                    Button("Add \(label) to Playlist") {
                        showAddItemToPlaylist = group
                    }
                    Button("Add \(label) to New Playlist “\(shortTitle(group.title))”") {
                        Task {
                            await playerVM.addEntireItemToNewPlaylist(
                                from: searchTrack(group),
                                named: group.title,
                                using: playlistVM)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear { searchFocused = true }   // cursor ready immediately
        }
    }

    // MARK: - Recent searches (shown when the query is empty)

    @ViewBuilder
    private var historyList: some View {
        if searchVM.recentSearches.isEmpty {
            ContentUnavailableView(
                "Search the Internet Archive",
                systemImage: "magnifyingglass",
                description: Text("Find music, albums and audiobooks.")
            )
        } else {
            List {
                Section {
                    ForEach(searchVM.recentSearches, id: \.self) { q in
                        Button {
                            searchVM.query = q
                        } label: {
                            Label(q, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                searchVM.removeHistory(q)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    HStack {
                        Text("Recent Searches")
                        Spacer()
                        Button("Clear") { searchVM.clearHistory() }
                            .font(.caption)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        List {
            ForEach(searchVM.displayedResults) { group in
                let dur = searchVM.durations[group.id] ?? group.duration
                HStack(spacing: 10) {
                    Image(systemName: kindIcon(group))
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(.body).fontWeight(.medium).lineLimit(2)
                        Text(group.creator)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 6) {
                            if let kind = searchVM.itemKinds[group.id] {
                                Text(kindLabel(kind))
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(Color.accentColor)
                            }
                            if let coll = group.collection,
                               !coll.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(coll)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let date = group.addedDate {
                            Text(date.formatted(.dateTime.year().month().day()))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if dur > 0 {
                        Text(Duration.seconds(dur)
                            .formatted(.time(pattern: .hourMinuteSecond)))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        selectedResult = group
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedResult = group }
                .task { searchVM.loadItemInfo(group) }
            }

            if searchVM.hasMorePages {
                ProgressView()
                    .task { await searchVM.loadNextPage() }
            }
        }
        .listStyle(.plain)
    }

    private func kindIcon(_ group: SearchViewModel.ResultGroup) -> String {
        switch searchVM.itemKinds[group.id] {
        case .book:  return "book.closed.fill"      // a book
        case .album: return "opticaldisc.fill"      // a record album
        case .track: return "music.note"            // a single track
        case nil:    return "waveform"              // not yet classified
        }
    }

    private func shortTitle(_ s: String, max: Int = 24) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }

    private func kindLabel(_ kind: SearchViewModel.ItemKind) -> String {
        switch kind {
        case .book:  return "Book"
        case .album: return "Album"
        case .track: return "Track"
        }
    }

    // Single-track Track for "Add to Playlist".
    private func searchTrack(_ group: SearchViewModel.ResultGroup) -> Track {
        Track(
            id: group.id, source: "internet_archive",
            title: group.title, artist: group.creator,
            duration: group.duration,
            streamURL: URL(string: "https://archive.org/download/\(group.id)")
                ?? URL(string: "https://archive.org")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1.0, rawCreator: group.creator,
            composer: nil, instruments: [],
            metadataConfidence: 0.0, addedDate: group.addedDate
        )
    }
}
