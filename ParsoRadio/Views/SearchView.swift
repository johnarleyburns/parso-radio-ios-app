import SwiftUI

struct SearchView: View {
    var dismissAll: (() -> Void)? = nil
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @StateObject private var searchVM: SearchViewModel
    @State private var showAddToPlaylist: Track? = nil
    @State private var showAddItemToPlaylist: SearchViewModel.ResultGroup? = nil
    @State private var selectedResult: SearchViewModel.ResultGroup? = nil
    @State private var infoGroup: SearchViewModel.ResultGroup? = nil
    @State private var failedTrackIds: Set<String> = []
    @State private var flashTrackId: String?
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
                        .accessibilityHidden(true)
                    TextField("Search music, audiobooks…", text: $searchVM.query)
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onChange(of: searchVM.query) { searchVM.searchChanged() }
                    if !searchVM.query.isEmpty {
                        Button { searchVM.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)

                // Scope filter: Both (default) / Music / Audiobooks.
                Picker("Search scope", selection: $searchVM.scope) {
                    ForEach(SearchViewModel.SearchScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: searchVM.scope) { searchVM.scopeChanged() }
                .accessibilityLabel("Filter results by type")

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
            .sheet(item: $infoGroup) { group in
                trackInfoSheet(group)
            }
            .onChange(of: playerVM.errorMessage) { _, msg in
                let failedId = playerVM.currentTrack?.id ?? playerVM.failedAuditionTrackId
                if let id = failedId, msg != nil {
                    failedTrackIds.insert(id)
                    flashTrackId = id
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        flashTrackId = nil
                    }
                }
            }
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
                let hasFailed = failedTrackIds.contains(group.id)
                let isFlashing = flashTrackId == group.id
                HStack(spacing: 10) {
                    Image(systemName: kindIcon(group))
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if hasFailed {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .scaleEffect(isFlashing ? 1.4 : 1.0)
                                    .animation(isFlashing ? .easeInOut(duration: 0.3).repeatCount(2, autoreverses: true) : .default, value: isFlashing)
                            }
                            Text(group.title)
                                .font(.body).fontWeight(.medium).lineLimit(2)
                        }
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
                    // The whole row is one actionable element below; this
                    // duplicate would just be noise for VoiceOver.
                    .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .onTapGesture { infoGroup = group }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens track info")
                .accessibilityAction { infoGroup = group }
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

    @ViewBuilder
    private func trackInfoSheet(_ group: SearchViewModel.ResultGroup) -> some View {
        NavigationStack {
            List {
                Section("Track Info") {
                    Text(group.title).font(.headline)
                    Text(group.creator).foregroundStyle(.secondary)
                    if group.duration > 0 {
                        Text(formatTime(group.duration))
                            .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
                if let kind = searchVM.itemKinds[group.id] {
                    Section("Type") {
                        Text(kindLabel(kind))
                    }
                }
                if let coll = group.collection,
                   !coll.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("Collection") {
                        Text(coll)
                    }
                }
                Section {
                    Text("ID: \(group.id)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Track Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { infoGroup = nil }
                }
            }
        }
    }

    private func formatTime(_ s: Double) -> String {
        let t = Int(s); let m = t / 60; let sec = t % 60
        return String(format: "%d:%02d", m, sec)
    }
}
